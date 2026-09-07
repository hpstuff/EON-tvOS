import SwiftUI

@main
struct EONTVApp: App {
  @State private var session = AppSession()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(session)
        .environment(session.clock)
        .environment(session.favorites)
        .environment(session.history)
        .preferredColorScheme(.dark)
    }
  }
}
