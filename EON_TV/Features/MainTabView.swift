import SwiftUI
import EONKit

/// The signed-in shell: the system sidebar (`.sidebarAdaptable`) carries the top-level sections
/// and floats over edge-to-edge content as Liquid Glass, collapsing to a slim indicator while
/// the viewer is in a section. The player is presented over everything so tab state, scroll
/// positions and focus survive a viewing session.
struct MainTabView: View {
  @Environment(AppSession.self) private var session
  @Environment(ContentStore.self) private var store
  @Environment(ProfileStore.self) private var profiles
  @Environment(FavoritesStore.self) private var favorites
  @State private var coordinator = PlaybackCoordinator()

  var body: some View {
    @Bindable var coordinator = coordinator

    sidebarChrome(
      TabView(selection: $coordinator.selectedSection) {
        Tab("Home", systemImage: "house.fill", value: .home) {
          HomeView()
        }
        Tab("Guide", systemImage: "list.bullet.rectangle.fill", value: .guide) {
          GuideView()
        }
        Tab("Channels", systemImage: "tv.fill", value: .channels) {
          ChannelsView()
        }
        Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
          SettingsView()
        }
        Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
          SearchView()
        }
      }
      .tabViewStyle(.sidebarAdaptable)
    )
    .environment(coordinator)
    .fullScreenCover(item: $coordinator.request) { request in
      PlayerScreen(request: request)
        .environment(coordinator)
        .environment(store)
    }
    .fullScreenCover(item: $coordinator.detail) { item in
      ProgramDetailView(item: item)
        .environment(coordinator)
        .environment(store)
    }
    .alert(
      favorites.lastError ?? "",
      isPresented: Binding(get: { favorites.lastError != nil }, set: { if !$0 { favorites.lastError = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Check your connection and try again.")
    }
  }

  /// tvOS 27 lets the sidebar carry a header and footer: the mark above the sections, the
  /// household's package below them.
  @ViewBuilder
  private func sidebarChrome(_ tabs: some View) -> some View {
    if #available(tvOS 27, *) {
      tabs
        .tabViewSidebarHeader {
          BrandMark(height: 40)
            .padding(.bottom, 8)
        }
        .tabViewSidebarFooter {
          VStack(alignment: .leading, spacing: 4) {
            if let profile = profiles.active, profiles.hasChoice {
              HStack(spacing: 12) {
                ProfileAvatar(profile: profile, size: 36)
                Text(profile.name)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(Theme.textPrimary)
              }
              .padding(.bottom, 6)
            }
            Text(session.household?.packageName ?? "EON TV")
              .font(.caption)
              .foregroundStyle(Theme.textSecondary)
            if session.isDemo {
              Text("Demo content")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .lineLimit(1)
          .padding(.top, 8)
        }
    } else {
      tabs
    }
  }
}
