import XCTest

/// Drives the app with the Siri Remote the way a viewer would and captures a screenshot after
/// every step. Runs against the demo backend so it needs no subscriber account.
final class RemoteWalkthroughTests: XCTestCase {
  private var app: XCUIApplication!
  private let remote = XCUIRemote.shared

  override func setUpWithError() throws {
    continueAfterFailure = true
    app = XCUIApplication()
    app.launchArguments = ["-demo"]
    // Run the walkthrough with the viewer's Text Size enlarged, e.g.
    // TEST_RUNNER_EON_TEXT_SIZE=UICTContentSizeCategoryAccessibilityL xcodebuild test …
    if let size = ProcessInfo.processInfo.environment["EON_TEXT_SIZE"] {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
    }
    app.launch()
    wait(6)
  }

  override func tearDownWithError() throws {
    app.terminate()
  }

  func testHomeFocusFlow() {
    snap("home-01-initial")
    press(.right); snap("home-02-start-over-focused")
    press(.right); snap("home-03-guide-button-focused")
    press(.down); snap("home-04-on-now-first-card")
    press(.right, times: 3); snap("home-05-on-now-fourth-card")
    press(.down); snap("home-06-next-shelf")
    press(.down); snap("home-07-third-shelf")
    press(.right, times: 6); snap("home-08-scrolled-right")
    press(.up, times: 3); snap("home-09-back-up")
  }

  func testGuideNavigation() {
    open(.guide, snappingSidebarAs: "guide-00-sidebar"); snap("guide-01-opened")
    press(.down); wait(1); snap("guide-02-first-move-down")
    press(.down); wait(1); snap("guide-03-second-move-down")
    press(.right); wait(1); snap("guide-04-right")
    press(.right); wait(1); snap("guide-05-right-again")
    press(.down, times: 3); wait(1); snap("guide-06-down-three-rows")
    press(.left, times: 4); wait(1); snap("guide-07-left-to-column")
    press(.down, times: 6); wait(1); snap("guide-08-column-down-six")
    press(.right); wait(1); snap("guide-09-back-into-grid")
    press(.up, times: 12); wait(1); snap("guide-10-back-to-top")
  }

  func testPlayerFlow() {
    press(.select); wait(7); snap("player-01-live")
    press(.playPause); wait(1); snap("player-02-paused")
    press(.playPause); wait(1)
    press(.up); wait(2); snap("player-03-after-up")
    press(.menu); wait(1); snap("player-04-after-menu")
    press(.menu); wait(2); snap("player-05-after-second-menu")
    press(.menu); wait(2); snap("player-06-after-third-menu")
    press(.menu); wait(2); snap("player-07-after-fourth-menu")
  }

  func testChannelsSearchSettings() {
    open(.channels); snap("channels-01-opened")
    press(.down); wait(1); snap("channels-02-filter-all")
    press(.right); wait(1); snap("channels-03-favorites")
    press(.right); wait(1); snap("channels-04-news")
    press(.down); wait(1); snap("channels-05-grid")
    press(.right, times: 2); wait(1); snap("channels-06-grid-right")
    open(.search); snap("search-01-opened")
    open(.settings); snap("settings-01-opened")
    press(.down); wait(1); snap("settings-02-first-row")
    press(.down, times: 3); wait(1); snap("settings-03-sign-out-row")
  }

  func testProgramDetailsAndContextMenu() {
    press(.down); press(.down); press(.down); wait(1); snap("details-00-a-shelf")
    // Long-press select opens the context menu on the focused card.
    remote.press(.select, forDuration: 1.2); wait(1); snap("details-01-context-menu")
    press(.menu); wait(1)
  }

  func testStartOverAndCatchUpFlow() {
    press(.right); press(.select); wait(8); snap("startover-01-playing")
    press(.playPause); wait(1); snap("startover-02-transport-bar")
    // Controls → hidden → out of the player; a further Menu would open the sidebar, and one
    // more would leave the app.
    press(.menu); wait(1); press(.menu); wait(1); press(.menu); wait(2)
    snap("startover-03-back-home")
    // Leaving the player lands on the sidebar; select re-enters Home on the hero's first action.
    press(.select); wait(1)
    // "Just Finished" shelf: third shelf down (On Now, Up Next, Just Finished) when nothing was resumed.
    press(.down, times: 4); wait(1); snap("catchup-01-shelf")
    press(.select); wait(8); snap("catchup-02-playing")
    press(.playPause); wait(1); snap("catchup-03-transport-bar")
    press(.menu); wait(1); press(.menu); wait(1); press(.menu); wait(2); snap("catchup-04-back-home")
  }

  func testProgramDetails() {
    press(.down, times: 3); wait(1); snap("details-00-up-next-shelf")
    press(.select); wait(2); snap("details-01-opened")
    press(.right); wait(1); snap("details-02-second-action")
    press(.down); wait(1); snap("details-03-day-shelf")
    press(.menu); wait(2); snap("details-04-back-home")
  }

  func testSearchScreen() {
    open(.search); snap("search-00-opened")
    press(.down); wait(1); snap("search-01-keyboard-focused")
  }

  func testSignInScreen() {
    app.terminate()
    app.launchArguments = []
    app.launch()
    wait(8); snap("signin-01")
    press(.down); wait(1); snap("signin-02-password-focused")
    press(.down); wait(1); snap("signin-03-button-focused")
    press(.select); wait(3); snap("signin-04-after-empty-submit")
  }

  func testPlayerTransportInteractions() {
    press(.select); wait(10); snap("transport-01-live-loaded")
    press(.playPause); wait(2); snap("transport-02-pause-bar")
    press(.playPause); wait(2); snap("transport-03-resume")
    press(.left); wait(3); snap("transport-04-after-left")
    press(.left); wait(3); snap("transport-05-after-left-2")
    press(.right); wait(3); snap("transport-06-after-right")
    wait(7); snap("transport-07-idle")
    press(.select); wait(2); snap("transport-08-after-select")
    press(.playPause); wait(2); snap("transport-09-after-playpause")
    press(.menu); wait(2); snap("transport-10-after-menu")
    press(.menu); wait(3); snap("transport-11-after-menu-2")
    press(.menu); wait(3); snap("transport-12-after-menu-3")
  }

  /// The panels are reachable only from the round buttons above the timeline: up from the
  /// hidden player shows the controls, up again enters the row on Start Over, and right walks
  /// it from there — Schedule, Channels, Audio & Subtitles.
  func testPlayerPanels() {
    press(.select); wait(9); snap("panels-01-playing")
    press(.up); wait(2); snap("panels-02-controls")
    press(.up); wait(1); snap("panels-03-button-row")
    press(.right); wait(1); snap("panels-04-schedule-button")
    press(.select); wait(2); snap("panels-05-schedule-panel")
    press(.right); wait(1); snap("panels-06-schedule-right")
    press(.menu); wait(1); snap("panels-07-back-to-controls")
    press(.up); wait(1); press(.right, times: 2); wait(1); snap("panels-08-channels-button")
    press(.select); wait(2); snap("panels-09-channels-panel")
    press(.right); press(.select); wait(8); snap("panels-10-switched-channel")
    press(.up); wait(1); press(.up); wait(1); press(.right, times: 3); wait(1); snap("panels-11-options-button")
    press(.select); wait(2); snap("panels-12-options-panel")
    press(.down); press(.select); wait(2); snap("panels-13-subtitle-selected")
    press(.menu); wait(1); press(.menu); wait(1); press(.menu); wait(2); snap("panels-14-home")
  }

  /// Skipping forward inside a finished programme must keep showing that programme, and a
  /// further skip made while the new stream is still loading must build on the requested
  /// position rather than falling through to live. Screenshots are taken during the load.
  func testCatchUpSeekStaysInProgramme() {
    // Fresh state: On Now, Up Next, Just Finished are the first three shelves.
    press(.down, times: 3); wait(1); snap("seek-00-just-finished-shelf")
    press(.select); wait(8); snap("seek-01-catch-up-playing")
    press(.right); snap("seek-02-preview-then-commit")
    // The commit fires 0.9 s after the press; the stream takes a moment longer to arrive.
    usleep(200_000); snap("seek-03-loading-after-commit")
    press(.right); snap("seek-04-second-skip-during-load")
    wait(4); snap("seek-05-settled")
    press(.right, times: 3); wait(4); snap("seek-06-after-three-skips")
    press(.left, times: 2); wait(4); snap("seek-07-after-two-back")
    press(.menu); wait(1); press(.menu); wait(1); press(.menu); wait(2); snap("seek-08-back-home")
  }

  // MARK: Helpers

  /// Top-level sections in sidebar order (Search is pinned last by its role).
  private enum Section: Int {
    case home, guide, channels, settings, search
  }

  /// Opens the sidebar from wherever focus is (Menu returns to it; a second Menu would leave
  /// the app), moves to the section and selects it, which switches the content and moves focus
  /// into it.
  private func open(_ section: Section, snappingSidebarAs name: String? = nil) {
    press(.menu); wait(1)
    if let name { snap(name) }
    press(.up, times: 5)
    press(.down, times: section.rawValue)
    press(.select); wait(3)
  }

  private func press(_ button: XCUIRemote.Button, times: Int = 1) {
    for _ in 0..<times {
      remote.press(button)
      usleep(350_000)
    }
    usleep(500_000)
  }

  private func wait(_ seconds: UInt32) {
    sleep(seconds)
  }

  private func snap(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
