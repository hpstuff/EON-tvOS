import SwiftUI
import EONKit

/// Account and device settings. Deliberately small: the platform exposes household details
/// and sign-out; everything else here is local state the viewer may want to reset.
struct SettingsView: View {
  @Environment(AppSession.self) private var session
  @Environment(ContentStore.self) private var store
  @Environment(FavoritesStore.self) private var favorites
  @Environment(WatchHistory.self) private var history
  @Environment(ProfileStore.self) private var profiles
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var confirmSignOut = false
  @State private var confirmClearHistory = false
  @FocusState private var focus: Focus?

  private enum Focus: Hashable {
    case switchProfile, askAtLaunch, refresh, clearHistory, clearFavorites, signOut
  }

  private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

  /// Account panel beside the actions at the default size; above them when text is large.
  private var layout: AnyLayout {
    isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 40))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 60))
  }

  var body: some View {
    ZStack {
      AmbientBackdrop(url: nil)
      ScrollView(.vertical) {
        layout {
          accountPanel
            .frame(width: isAccessibilitySize ? nil : 720)
          VStack(alignment: .leading, spacing: 26) {
            Text("Settings")
              .font(.screenTitle)
              .foregroundStyle(Theme.textPrimary)

            if profiles.hasChoice {
              settingsRow(
                title: "Switch Profile",
                detail: "Watching as \(profiles.active?.name ?? "the default profile"). Favourites and history follow the profile.",
                symbol: "person.2",
                focus: .switchProfile
              ) {
                session.switchProfile()
              }

              settingsRow(
                title: profiles.askAtLaunch ? "Ask Who's Watching: On" : "Ask Who's Watching: Off",
                detail: profiles.askAtLaunch
                  ? "Choose a profile each time EON TV opens."
                  : "EON TV opens as the last profile used.",
                symbol: profiles.askAtLaunch ? "checkmark.circle" : "circle",
                focus: .askAtLaunch
              ) {
                profiles.askAtLaunch.toggle()
              }
            }

            settingsRow(
              title: "Refresh channels & guide",
              detail: "Reload the line-up and today's guide from EON.",
              symbol: "arrow.clockwise",
              focus: .refresh
            ) {
              Task { await store.loadChannels(silently: true); await store.refreshIfStale() }
            }

            settingsRow(
              title: "Clear Continue Watching",
              detail: "Removes resume positions and recently watched channels.",
              symbol: "clock.arrow.circlepath",
              focus: .clearHistory
            ) {
              confirmClearHistory = true
            }

            settingsRow(
              title: "Clear Favorites",
              detail: "Removes all \(favorites.ids.count) favourite channels from this profile, here and in the EON web app.",
              symbol: "heart.slash",
              focus: .clearFavorites
            ) {
              favorites.removeAll()
            }

            settingsRow(
              title: "Sign Out",
              detail: "You'll need your EON username and password, or a code from the EON portal, to sign back in.",
              symbol: "rectangle.portrait.and.arrow.right",
              focus: .signOut,
              destructive: true
            ) {
              confirmSignOut = true
            }

            Text("EON TV for Apple TV · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))\(session.isDemo ? " · Demo content" : "")")
              .font(.caption2.weight(.regular))
              .foregroundStyle(Theme.textTertiary)
              .padding(.top, 20)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .focusSection()
        }
        .padding(.horizontal, Theme.screenMargin)
        .padding(.top, Theme.contentTop + 8)
        .padding(.bottom, Theme.verticalMargin)
      }
      .scrollClipDisabled()
    }
    .defaultFocus($focus, .refresh)
    .alert("Sign out of EON TV?", isPresented: $confirmSignOut) {
      Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Favourites stay with your EON account. Continue Watching will be cleared.")
    }
    .alert("Clear Continue Watching?", isPresented: $confirmClearHistory) {
      Button("Clear", role: .destructive) { history.clear() }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var accountPanel: some View {
    VStack(alignment: .leading, spacing: 26) {
      BrandMark(height: 56)
      VStack(alignment: .leading, spacing: 8) {
        Text(session.household?.packageName ?? "EON TV")
          .font(.headline.weight(.regular))
          .foregroundStyle(Theme.textPrimary)
        Text("Your package")
          .font(.caption2)
          .foregroundStyle(Theme.textTertiary)
      }
      Divider().overlay(Theme.stroke)
      if let profile = profiles.active {
        HStack(spacing: 20) {
          ProfileAvatar(profile: profile, size: 64)
          VStack(alignment: .leading, spacing: 4) {
            Text(profile.name)
              .font(.headline.weight(.regular))
              .foregroundStyle(Theme.textPrimary)
            Text("Profile")
              .font(.caption2)
              .foregroundStyle(Theme.textTertiary)
          }
        }
        Divider().overlay(Theme.stroke)
      }
      detail(label: "Contract", value: session.household?.contractNumber ?? "—")
      detail(label: "This Apple TV", value: session.device.map { $0.friendlyId.isEmpty ? $0.deviceNumber : $0.friendlyId } ?? "—")
      detail(label: "Channels", value: "\(store.channels.count) subscribed")
      detail(label: "Categories", value: "\(store.browsableCategories.count)")
      detail(label: "Catch-up", value: "\(store.channels.filter(\.canCatchUp).count) channels")
    }
    .padding(44)
    .glassPanel()
  }

  private func detail(label: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
      Spacer()
      Text(value)
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.textPrimary)
        .multilineTextAlignment(.trailing)
    }
  }

  /// A full-width glass button: the system draws the platter and the focus lift.
  private func settingsRow(title: String, detail: String, symbol: String, focus value: Focus, destructive: Bool = false, action: @escaping () -> Void) -> some View {
    Button(role: destructive ? .destructive : nil, action: action) {
      HStack(spacing: 24) {
        Image(systemName: symbol)
          .font(.body)
          .frame(width: 44)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.body)
          Text(detail)
            .font(.caption2.weight(.regular))
            .opacity(0.7)
        }
        .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .opacity(0.6)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)
    }
    .buttonStyle(.glass)
    .focused($focus, equals: value)
  }
}
