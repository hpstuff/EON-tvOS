import SwiftUI

/// Switches between launch, sign-in and the signed-in experience. Transitions cross-fade so
/// the app never flashes an empty frame between states.
struct RootView: View {
  @Environment(AppSession.self) private var session
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ZStack {
      Theme.backgroundGradient.ignoresSafeArea()

      switch session.phase {
      case .launching:
        LaunchView()
          .transition(.opacity)

      case .unavailable(let message):
        StatusView(
          symbol: "wifi.exclamationmark",
          title: "EON TV is unavailable",
          message: message,
          actionTitle: "Try Again",
          action: { session.boot() }
        )
        .transition(.opacity)

      case .signedOut:
        SignInView()
          .transition(.opacity)

      case .signedIn:
        if let content = session.content {
          MainTabView()
            .environment(content)
            .transition(.opacity)
        }
      }
    }
    .animation(.easeInOut(duration: 0.4), value: session.phase)
    .task {
      session.boot(demo: ProcessInfo.processInfo.arguments.contains("-demo"))
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { session.didBecomeActive() }
    }
  }
}

/// Brand moment shown while the platform configuration and session are resolved: the mark
/// draws its spectrum line in, then breathes until the app is ready.
struct LaunchView: View {
  @State private var lineProgress: CGFloat = 0
  @State private var breathing = false

  var body: some View {
    ZStack {
      AuroraWaves(seed: 2, intensity: 0.35, drifting: true)
        .ignoresSafeArea()
      BrandMark(height: 168, lineProgress: lineProgress)
        .opacity(breathing ? 0.86 : 1)
    }
    .onAppear {
      withAnimation(.easeOut(duration: 1.2)) { lineProgress = 1 }
      withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(1.2)) { breathing = true }
    }
  }
}
