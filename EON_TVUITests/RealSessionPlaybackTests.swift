import XCTest

/// Diagnostic walkthrough of the player against real streams. Requires a simulator that is
/// already signed in; skips itself otherwise so the regular suite stays deterministic.
final class RealSessionPlaybackTests: XCTestCase {
  private var app: XCUIApplication!
  private let remote = XCUIRemote.shared

  override func setUpWithError() throws {
    continueAfterFailure = true
    app = XCUIApplication()
    app.launchArguments = []
    app.launch()
    // Home's primary action only exists once a real session has loaded the line-up.
    guard app.buttons["Watch Live"].waitForExistence(timeout: 25) else {
      throw XCTSkip("No signed-in session on this simulator")
    }
    wait(3)
  }

  override func tearDownWithError() throws {
    app.terminate()
  }

  func testLiveTransportInteractions() {
    snap("real-00-home")
    press(.select); wait(12); snap("real-01-live-loaded")
    press(.playPause); wait(2); snap("real-02-pause-bar")
    press(.playPause); wait(2); snap("real-03-resume")
    press(.left); wait(3); snap("real-04-after-left")
    press(.left); wait(3); snap("real-05-after-left-2")
    press(.right); wait(3); snap("real-06-after-right")
    wait(7); snap("real-07-idle-controls-hidden")
    press(.select); wait(2); snap("real-08-after-select")
    press(.playPause); wait(2); snap("real-09-after-playpause")
    press(.down); wait(2); snap("real-10-after-down")
    press(.menu); wait(2); snap("real-11-after-menu")
    press(.menu); wait(2); snap("real-12-after-menu-2")
    press(.menu); wait(3); snap("real-13-after-menu-3")
    press(.menu); wait(3); snap("real-14-after-menu-4")
  }

  func testStartOverTransportInteractions() {
    press(.right); press(.select); wait(12); snap("so-01-loaded")
    press(.playPause); wait(2); snap("so-02-pause-bar")
    press(.right); wait(3); snap("so-03-after-right")
    press(.right); wait(3); snap("so-04-after-right-2")
    press(.left); wait(3); snap("so-05-after-left")
    press(.playPause); wait(3); snap("so-06-resumed")
    wait(7); snap("so-07-idle")
    press(.select); wait(2); snap("so-08-after-select")
    press(.menu); wait(2); snap("so-09-after-menu")
    press(.menu); wait(3); snap("so-10-after-menu-2")
    press(.menu); wait(3); snap("so-11-after-menu-3")
  }

  func testBackButtonLayers() {
    press(.select); wait(10); snap("back-01-playing-hidden")
    press(.select); wait(2); snap("back-02-controls")
    press(.menu); wait(2); snap("back-03-after-back-expect-hidden")
    press(.playPause); wait(2); snap("back-04-paused-controls")
    press(.menu); wait(2); snap("back-05-after-back-expect-hidden-paused")
    press(.playPause); wait(3); snap("back-06-resumed")
    press(.down); wait(2); snap("back-07-schedule-panel")
    press(.menu); wait(2); snap("back-08-after-back-expect-controls")
    press(.menu); wait(2); snap("back-09-after-back-expect-hidden")
    press(.up); wait(2); snap("back-10-channels-panel")
    press(.menu); wait(2); snap("back-11-after-back-expect-controls")
    press(.down); wait(1); press(.right, times: 2); wait(1); snap("back-12-schedule-button")
    press(.select); wait(2); snap("back-13-schedule-from-button")
    press(.menu); wait(2); snap("back-14-after-back-expect-controls")
    press(.menu); wait(2); snap("back-15-after-back-expect-hidden")
    press(.menu); wait(3); snap("back-16-after-back-expect-home")
  }

  func testBackAfterTimeshiftButtons() {
    press(.select); wait(10)
    press(.select); wait(2); press(.down); wait(1); press(.right); wait(1); snap("tsb-01-start-over-focused")
    press(.select); wait(6); snap("tsb-02-after-start-over")
    press(.menu); wait(2); snap("tsb-03-after-back-expect-hidden")
    press(.select); wait(2); press(.down); wait(1); press(.right); wait(1); snap("tsb-04-go-live-focused")
    press(.select); wait(6); snap("tsb-05-after-go-live")
    press(.menu); wait(2); snap("tsb-06-after-back-expect-hidden")
    press(.menu); wait(3); snap("tsb-07-after-back-expect-home")
  }

  /// Skipping inside a finished programme on a real timeshift stream. The programme shown and
  /// the timeline must stay put while each new stream loads, and a skip made while one is still
  /// loading must build on the requested position rather than fall through to live.
  func testCatchUpSeekStaysInProgramme() {
    // Fresh state: On Now, Up Next, Just Finished are the first three shelves once the guide is in.
    wait(6)
    press(.down, times: 3); wait(1); snap("rseek-00-just-finished-shelf")
    press(.select); wait(12); snap("rseek-01-catch-up-playing")
    press(.right); usleep(300_000); snap("rseek-02-loading-after-commit")
    press(.right); snap("rseek-03-second-skip-during-load")
    wait(6); snap("rseek-04-settled")
    press(.right, times: 3); wait(6); snap("rseek-05-after-three-skips")
    press(.left, times: 2); wait(6); snap("rseek-06-after-two-back")
    press(.menu); wait(1); press(.menu); wait(2); snap("rseek-07-back-home")
  }

  private func press(_ button: XCUIRemote.Button, times: Int = 1) {
    for _ in 0..<times {
      remote.press(button)
      usleep(350_000)
    }
    usleep(500_000)
  }

  private func wait(_ seconds: UInt32) { sleep(seconds) }

  private func snap(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
