import XCTest

/// Moves focus around the programme guide the way a viewer browsing it would, so the work each
/// remote press costs can be recorded (Instruments' SwiftUI template attached to the app) and
/// compared between builds with the CPU metric below. Runs against the demo backend.
final class GuidePerformanceTests: XCTestCase {
  private var app: XCUIApplication!
  private let remote = XCUIRemote.shared

  override func setUpWithError() throws {
    continueAfterFailure = true
    app = XCUIApplication()
    // TEST_RUNNER_EON_ATTACH=1 drives an app that Instruments has already launched with `-demo`
    // (the SwiftUI instrument only records a process it launched itself).
    if ProcessInfo.processInfo.environment["EON_ATTACH"] == nil {
      app.launchArguments = ["-demo"]
      app.launch()
    }
    sleep(6)
    openGuide()
  }

  override func tearDownWithError() throws {
    app.terminate()
  }

  /// A long sweep for tracing: across the day, down the line-up and back, twice.
  func testGuideNavigationSweep() {
    for _ in 0..<2 {
      press(.right, times: 8)
      press(.down, times: 6)
      press(.left, times: 8)
      press(.up, times: 6)
    }
  }

  /// Sits on the guide without pressing anything, so work that runs with nothing happening
  /// (continuous animation, timers) can be told apart from the cost of a press.
  func testGuideIdle() {
    sleep(25)
  }

  /// CPU time the app spends on twenty presses that return focus to where it started.
  func testGuideNavigationCPU() {
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    measure(metrics: [XCTCPUMetric(application: app), XCTClockMetric()], options: options) {
      press(.right, times: 5)
      press(.down, times: 5)
      press(.left, times: 5)
      press(.up, times: 5)
    }
  }

  // MARK: Helpers

  /// Menu opens the sidebar; the guide is the second section.
  private func openGuide() {
    remote.press(.menu); sleep(1)
    for _ in 0..<5 { remote.press(.up); usleep(300_000) }
    remote.press(.down); usleep(300_000)
    remote.press(.select); sleep(3)
  }

  private func press(_ button: XCUIRemote.Button, times: Int) {
    for _ in 0..<times {
      remote.press(button)
      usleep(300_000)
    }
    usleep(400_000)
  }
}
