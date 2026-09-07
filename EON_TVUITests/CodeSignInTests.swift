import XCTest

/// Drives the sign-in screen's code option against the real platform: the app registers this
/// Apple TV, requests a one-time code and waits for it to be confirmed. No account is needed
/// because the test stops at the waiting state; it skips itself when the simulator is already
/// signed in, since the sign-in screen is then never shown.
final class CodeSignInTests: XCTestCase {
  private var app: XCUIApplication!
  private let remote = XCUIRemote.shared

  override func setUpWithError() throws {
    continueAfterFailure = true
    app = XCUIApplication()
    app.launchArguments = []
    app.launch()
    guard app.buttons["Code"].waitForExistence(timeout: 25) else {
      throw XCTSkip("This simulator is signed in; the sign-in screen is not shown")
    }
    wait(1)
  }

  override func tearDownWithError() throws {
    app.terminate()
  }

  func testCodeOptionRegistersDeviceAndShowsCode() {
    snap("code-01-sign-in-password-mode")
    press(.up); wait(1); press(.right); wait(1); snap("code-02-code-option-focused")
    press(.select); wait(1); snap("code-03-requesting")

    let waiting = app.staticTexts["Waiting for you to confirm the code…"]
    XCTAssertTrue(waiting.waitForExistence(timeout: 25), "Device registration or the code request failed")
    wait(1); snap("code-04-waiting-with-code")

    // The code is announced as "Code R 7 P U C C" for VoiceOver, one character at a time.
    let code = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "Code( [A-Z0-9]){6}")).firstMatch
    XCTAssertTrue(code.exists, "A six-character code should be on screen")
    XCTAssertTrue(app.staticTexts["Expires in"].exists)

    // Let the poll run a couple of cycles: an unconfirmed code must keep waiting, not fail.
    wait(12); snap("code-05-still-waiting-after-polls")
    XCTAssertTrue(waiting.exists)

    press(.left); wait(1); press(.select); wait(1); snap("code-06-back-to-password")
    XCTAssertTrue(app.secureTextFields.firstMatch.exists)
    XCTAssertFalse(waiting.exists)
  }

  private func press(_ button: XCUIRemote.Button, times: Int = 1) {
    for _ in 0..<times {
      remote.press(button)
      usleep(350_000)
    }
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
