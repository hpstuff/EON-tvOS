import SwiftUI

/// The signed-in shell: a standard tvOS tab bar with the player presented over everything so
/// tab state, scroll positions and focus survive a viewing session.
struct MainTabView: View {
  @Environment(ContentStore.self) private var store
  @State private var coordinator = PlaybackCoordinator()

  var body: some View {
    @Bindable var coordinator = coordinator

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
      Tab("Search", systemImage: "magnifyingglass", value: .search) {
        SearchView()
      }
      Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
        SettingsView()
      }
    }
    .environment(coordinator)
    .tint(.white)
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
  }
}
