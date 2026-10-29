import Foundation
import EONKit
import Observation

/// The household's viewer profiles and which one this Apple TV acts as. The platform carries
/// the active profile in the session's token, so switching re-issues the token and everything
/// profile-scoped (favourites, the line-up's age limits, local history) is reloaded after it.
@Observable
final class ProfileStore {
  private static let askAtLaunchKey = "eon.profiles.askAtLaunch"

  private(set) var profiles: [Profile] = []
  private(set) var activeID: Profile.ID?

  /// Whether "Who's watching?" opens at launch when the household has several profiles.
  var askAtLaunch: Bool {
    didSet { UserDefaults.standard.set(askAtLaunch, forKey: Self.askAtLaunchKey) }
  }

  init() {
    askAtLaunch = UserDefaults.standard.object(forKey: Self.askAtLaunchKey) as? Bool ?? true
  }

  var active: Profile? {
    profiles.first { $0.id == activeID } ?? profiles.first { $0.isDefault }
  }

  var hasChoice: Bool { profiles.count > 1 }

  func load(from repository: ProfilesRepository) async throws {
    profiles = try await repository.getProfiles()
    activeID = await repository.activeProfileID()
  }

  /// Makes `profile` the session's profile, with its `pin` when it is protected. A no-op when
  /// it already is.
  func activate(_ profile: Profile, pin: String?, using repository: ProfilesRepository) async throws {
    if profile.id != activeID {
      try await repository.activate(profileID: profile.id, pin: pin)
    }
    activeID = profile.id
  }

  func clear() {
    profiles = []
    activeID = nil
  }
}
