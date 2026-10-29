import SwiftUI
import EONKit

/// "Who's watching?": the household's profiles as large avatars. Picking one re-issues the
/// session for that profile, after the PIN when the profile is protected.
struct ProfilePickerView: View {
  @Environment(AppSession.self) private var session
  @Environment(ProfileStore.self) private var profiles

  @State private var pinFor: Profile?
  @State private var busy: Profile.ID?
  @State private var error: String?
  @FocusState private var focus: Focus?

  private enum Focus: Hashable {
    case profile(Profile.ID), askAtLaunch
  }

  var body: some View {
    ZStack {
      AmbientBackdrop(url: nil)

      if let profile = pinFor {
        PinEntryView(
          title: "Enter the PIN for \(profile.name)",
          message: "Enter the 4-digit PIN for this profile.",
          submit: { await switchTo(profile, pin: $0) },
          onSuccess: { pinFor = nil },
          onCancel: { pinFor = nil; focus = .profile(profile.id) }
        )
        .transition(.opacity)
      } else {
        picker
          .transition(.opacity)
      }
    }
    .animation(Theme.crossfade, value: pinFor)
  }

  private var picker: some View {
    @Bindable var profiles = profiles

    return VStack(spacing: 64) {
      BrandMark(height: 56)
      Text("Who's watching?")
        .font(.title2.weight(.regular))
        .foregroundStyle(Theme.textPrimary)

      ScrollView(.horizontal) {
        HStack(spacing: 56) {
          ForEach(profiles.profiles) { profile in
            tile(profile)
          }
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.vertical, 40)
        .frame(minWidth: 1920 - 2 * Theme.screenMargin)
      }
      .scrollClipDisabled()
      .focusSection()

      Text(error ?? " ")
        .font(.caption.weight(.regular))
        .foregroundStyle(Theme.textSecondary)
        .opacity(error == nil ? 0 : 1)

      Button {
        profiles.askAtLaunch.toggle()
      } label: {
        Label(
          profiles.askAtLaunch ? "Ask every time EON TV opens" : "Use this choice next time",
          systemImage: profiles.askAtLaunch ? "checkmark.circle.fill" : "circle"
        )
        .font(.caption)
      }
      .buttonStyle(.glass)
      .focused($focus, equals: .askAtLaunch)
    }
    .onAppear { if focus == nil { focus = initialFocus } }
    // Back returns to the profile the session already has, when there is one.
    .onExitCommand {
      if let active = profiles.active, busy == nil { select(active) }
    }
  }

  private var initialFocus: Focus? {
    (profiles.active ?? profiles.profiles.first).map { .profile($0.id) }
  }

  private func tile(_ profile: Profile) -> some View {
    Button {
      if profile.pinProtected && profile.id != profiles.activeID {
        pinFor = profile
      } else {
        select(profile)
      }
    } label: {
      ProfileTileLabel(profile: profile, isBusy: busy == profile.id)
    }
    .buttonStyle(.bare)
    .focused($focus, equals: .profile(profile.id))
    .disabled(busy != nil)
    .accessibilityLabel(profile.pinProtected ? "\(profile.name), PIN protected" : profile.name)
  }

  private func select(_ profile: Profile) {
    guard busy == nil else { return }
    busy = profile.id
    error = nil
    Task {
      if case .failed(let message) = await switchTo(profile, pin: nil) {
        error = message
        focus = .profile(profile.id)
      }
      busy = nil
    }
  }

  /// Switches the session; the platform checks a protected profile's PIN.
  private func switchTo(_ profile: Profile, pin: String?) async -> ParentalGate.Outcome {
    do {
      try await session.choose(profile, pin: pin)
      return .unlocked
    } catch AuthError.wrongPin {
      return .wrongPin
    } catch {
      return .failed(ErrorPresenter.message(for: error, context: .session))
    }
  }
}

/// A profile tile that draws its own focus: the avatar lifts and gains a white ring.
private struct ProfileTileLabel: View {
  let profile: Profile
  let isBusy: Bool
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    VStack(spacing: 28) {
      ZStack {
        ProfileAvatar(profile: profile, size: 220)
          .overlay(Circle().strokeBorder(.white, lineWidth: isFocused ? 6 : 0))
          .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 14)
        if isBusy {
          ProgressView()
        }
      }
      .scaleEffect(isFocused ? 1.12 : 1)

      HStack(spacing: 10) {
        Text(profile.name)
          .font(.headline.weight(isFocused ? .semibold : .regular))
          .lineLimit(1)
        if profile.pinProtected {
          Image(systemName: "lock.fill")
            .font(.caption)
        }
      }
      .foregroundStyle(isFocused ? Theme.textPrimary : Theme.textSecondary)
    }
    .padding(28)
    .animation(Theme.focusAnimation, value: isFocused)
  }
}

/// A profile's avatar from the platform, or its initial when there is none.
struct ProfileAvatar: View {
  @Environment(AppSession.self) private var session
  let profile: Profile
  var size: CGFloat = 64

  private var url: URL? {
    guard let path = profile.avatarPath, let baseURL = session.backend?.baseURL else { return nil }
    return URL(string: ImageHost.url(baseURL: baseURL) + path)
  }

  var body: some View {
    RemoteImage(url: url, contentMode: .fill) {
      ZStack {
        Circle().fill(Theme.stroke)
        Text(profile.name.prefix(1).uppercased())
          .font(.system(size: size * 0.42, weight: .semibold))
          .foregroundStyle(.white)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}
