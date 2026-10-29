import Foundation
import EONKit
import Observation

/// Owns the process-wide lifecycle: platform bootstrap, authentication state and the stores
/// that outlive individual screens. Screens read it from the environment.
@Observable
final class AppSession {
  enum Phase: Equatable {
    case launching
    case unavailable(String)
    case signedOut
    /// Signed in, waiting for the viewer to say who's watching.
    case choosingProfile
    case signedIn
  }

  /// Progress of the sign-in-with-a-code option: the platform issues an `xxxx-xxxx` code for
  /// this device, the viewer confirms it on the provider's website, and the app polls until it
  /// is accepted (the OAuth device-code grant).
  enum CodeSignIn: Equatable {
    case idle
    case requesting
    case waiting(OneTimeCode, expiresAt: Date)
    case expired
    case failed(String)
  }

  private(set) var phase: Phase = .launching
  private(set) var backend: Backend?
  private(set) var household: Household?
  private(set) var content: ContentStore?
  /// This installation's registration with the platform, once known.
  private(set) var device: Device?

  let clock = LiveClock()
  let favorites = FavoritesStore()
  let history = WatchHistory()
  let profiles = ProfileStore()
  let parentalGate = ParentalGate()

  private(set) var isSigningIn = false
  var signInError: String?
  private(set) var codeSignIn: CodeSignIn = .idle
  private var bootTask: Task<Void, Never>?
  private var codeTask: Task<Void, Never>?


  var isDemo: Bool { backend?.isDemo ?? false }

  // MARK: Lifecycle

  func boot(demo: Bool = false) {
    bootTask?.cancel()
    bootTask = Task { await performBoot(demo: demo) }
  }

  private func performBoot(demo: Bool) async {
    phase = .launching
    signInError = nil
    do {
      let backend: Backend
      #if DEBUG
      backend = demo ? DemoBackend.make() : try await BackendFactory.makeLive()
      #else
      backend = try await BackendFactory.makeLive()
      #endif
      self.backend = backend
      clock.start()
      Task { try? await backend.syncClock(); clock.tick() }

      guard await backend.hasStoredSession() else {
        phase = .signedOut
        return
      }
      do {
        let household = try await backend.auth.getHousehold()
        enter(household)
      } catch let error as URLError {
        phase = .unavailable(ErrorPresenter.message(for: error, context: .session))
      } catch {
        // The stored session is no longer valid (or the provider removed this device): drop
        // it so the next sign-in registers the device afresh, and ask for credentials again.
        await backend.clearSession()
        phase = .signedOut
      }
    } catch {
      phase = .unavailable(ErrorPresenter.message(for: error, context: .session))
    }
  }

  func signIn(username: String, password: String) async {
    guard let backend, !isSigningIn else { return }
    let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !user.isEmpty, !password.isEmpty else {
      signInError = "Enter your username and password."
      return
    }
    cancelCodeSignIn()
    isSigningIn = true
    signInError = nil
    defer { isSigningIn = false }
    do {
      let household = try await backend.auth.login(username: user, password: password)
      enter(household)
    } catch {
      signInError = ErrorPresenter.message(for: error, context: .signIn)
    }
  }

  /// Requests a one-time code for this Apple TV and keeps offering it to the platform until
  /// the viewer confirms it in the provider's portal, it expires, or `cancelCodeSignIn` is called.
  func startCodeSignIn() {
    codeTask?.cancel()
    signInError = nil
    codeTask = Task { await runCodeSignIn() }
  }

  func cancelCodeSignIn() {
    codeTask?.cancel()
    codeTask = nil
    codeSignIn = .idle
  }

  private func runCodeSignIn() async {
    guard let backend else { return }
    codeSignIn = .requesting
    let code: OneTimeCode
    do {
      code = try await backend.auth.requestOneTimeCode()
    } catch {
      if !Task.isCancelled { codeSignIn = .failed(ErrorPresenter.message(for: error, context: .signIn)) }
      return
    }
    let expiresAt = Date().addingTimeInterval(TimeInterval(code.expiresInSeconds))
    codeSignIn = .waiting(code, expiresAt: expiresAt)

    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(code.pollInterval))
      if Task.isCancelled { return }
      if Date() >= expiresAt {
        codeSignIn = .expired
        return
      }
      do {
        let household = try await backend.auth.login(oneTimeCode: code)
        if Task.isCancelled { return }
        codeSignIn = .idle
        enter(household)
        return
      } catch AuthError.codeNotConfirmed {
        continue
      } catch AuthError.codeExpired {
        if !Task.isCancelled { codeSignIn = .expired }
        return
      } catch is URLError {
        // A network blip should not abandon a code the viewer may be typing right now.
        continue
      } catch {
        if !Task.isCancelled { codeSignIn = .failed(ErrorPresenter.message(for: error, context: .signIn)) }
        return
      }
    }
  }

  func signOut() async {
    cancelCodeSignIn()
    await backend?.clearSession()
    stopContent()
    household = nil
    device = nil
    history.clear()
    profiles.clear()
    phase = .signedOut
  }

  /// The app left the foreground: adult channels need the PIN again.
  func didResignActive() {
    parentalGate.lock()
  }

  /// Called when the scene returns to the foreground: re-sync the clock and top up content
  /// without tearing down any screen state.
  func didBecomeActive() {
    guard let backend, phase == .signedIn else { return }
    Task {
      try? await backend.syncClock()
      clock.tick()
      await content?.refreshIfStale()
    }
  }

  private func enter(_ household: Household) {
    guard let backend else { return }
    self.household = household
    parentalGate.attach(backend.parental)
    Task { device = await backend.auth.registeredDevice() }
    Task { await resolveProfile() }
  }

  // MARK: Profiles

  /// Asks who's watching when the household has several profiles (unless the viewer turned
  /// that off), otherwise carries on as the profile the session already acts as.
  private func resolveProfile() async {
    guard let backend else { return }
    phase = .launching
    // Without profiles the session simply stays on the platform's default.
    try? await profiles.load(from: backend.profiles)
    if profiles.hasChoice && profiles.askAtLaunch {
      phase = .choosingProfile
    } else {
      startContent()
    }
  }

  /// Switches the session to `profile` and opens its content. A protected profile needs its
  /// `pin`; the platform checks it and a wrong one throws `AuthError.wrongPin`.
  func choose(_ profile: Profile, pin: String? = nil) async throws {
    guard let backend else { return }
    try await profiles.activate(profile, pin: pin, using: backend.profiles)
    startContent()
  }

  /// Leaves the current profile's content and shows "Who's watching?".
  func switchProfile() {
    guard phase == .signedIn else { return }
    stopContent()
    phase = .choosingProfile
  }

  private func startContent() {
    guard let backend else { return }
    parentalGate.lock()
    history.use(profileID: profiles.activeID)
    let store = ContentStore(backend: backend, clock: clock, profile: profiles.active)
    content = store
    phase = .signedIn
    Task { await store.loadInitial() }
    Task { await favorites.attach(backend.favorites) }
  }

  private func stopContent() {
    content?.stop()
    content = nil
    favorites.detach()
    parentalGate.lock()
  }
}
