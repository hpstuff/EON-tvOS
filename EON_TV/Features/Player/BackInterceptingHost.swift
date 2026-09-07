import OSLog
import SwiftUI
import UIKit

/// Funnels every Back press, whichever UIKit path delivered it, into one observable event.
///
/// A single physical press can surface twice (SwiftUI's exit command and the UIKit press, or a
/// key command and its press), so near-simultaneous reports collapse into one.
@Observable
final class BackRelay {
  private(set) var count = 0
  @ObservationIgnored private var last: Date = .distantPast

  func fire() {
    let now = Date()
    guard now.timeIntervalSince(last) > 0.15 else { return }
    last = now
    count += 1
  }
}

/// Slides across the Siri Remote touchpad, relayed from the UIKit container to the SwiftUI
/// screen. `moved` carries the finger's travel since `began` as a fraction of the screen width.
@Observable
final class ScrubRelay {
  enum Event: Equatable {
    case began
    case moved(fraction: Double)
    case ended
  }

  private(set) var event: Event = .ended
  private(set) var count = 0

  func post(_ event: Event) {
    self.event = event
    count += 1
  }
}

/// Hosts SwiftUI content inside a UIKit container that sees remote input before the
/// presentation layer does.
///
/// SwiftUI's `onExitCommand` fires for Siri Remote Menu presses, but a hardware-keyboard Escape
/// (what the Simulator and Bluetooth keyboards send) bypasses it and falls through to the
/// enclosing full-screen cover, which dismisses. The container swallows both kinds of press and
/// reports them through `onBack`, so the hosted content decides what Back means. It also
/// recognises touchpad slides, which SwiftUI only exposes as discrete move commands, and
/// reports them through `onScrub` so the player can scrub continuously.
struct BackInterceptingHost<Content: View>: UIViewControllerRepresentable {
  let onBack: () -> Void
  var onScrub: (ScrubRelay.Event) -> Void = { _ in }
  @ViewBuilder let content: () -> Content

  func makeUIViewController(context: Context) -> BackInterceptingController {
    let controller = BackInterceptingController(rootView: rootView(context))
    controller.onBack = onBack
    controller.onScrub = onScrub
    return controller
  }

  func updateUIViewController(_ controller: BackInterceptingController, context: Context) {
    controller.onBack = onBack
    controller.onScrub = onScrub
    controller.host.rootView = rootView(context)
  }

  /// The hosted hierarchy is a separate SwiftUI graph; hand it the full environment so stores,
  /// the coordinator and styling resolve exactly as they would inline.
  private func rootView(_ context: Context) -> AnyView {
    AnyView(content().environment(\.self, context.environment))
  }
}

final class BackInterceptingController: UIViewController {
  var onBack: () -> Void = {}
  var onScrub: (ScrubRelay.Event) -> Void = { _ in }
  let host: UIHostingController<AnyView>

  init(rootView: AnyView) {
    host = UIHostingController(rootView: rootView)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("BackInterceptingController is created in code")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    addChild(host)
    host.view.frame = view.bounds
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.view.backgroundColor = .clear
    view.addSubview(host.view)
    host.didMove(toParent: self)

    // Indirect touches reach the focused view and its ancestors, so a recognizer here sees every
    // touchpad slide in the player. It never cancels the touches: the focus engine keeps moving
    // focus between controls, and the screen decides when a slide means scrubbing.
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
    pan.cancelsTouchesInView = false
    pan.delaysTouchesBegan = false
    pan.delaysTouchesEnded = false
    view.addGestureRecognizer(pan)
  }

  @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      onScrub(.began)
    case .changed:
      let width = view.bounds.width
      guard width > 0 else { return }
      onScrub(.moved(fraction: Double(gesture.translation(in: view).x / width)))
    case .ended, .cancelled, .failed:
      onScrub(.ended)
    default:
      break
    }
  }

  // Presses start at the focused view and bubble through the hosting controller to here; what
  // the SwiftUI content did not consume arrives in these overrides.

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    log("began", presses)
    let rest = presses.filter { !Self.isBack($0) }
    if !rest.isEmpty { super.pressesBegan(rest, with: event) }
  }

  override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    let rest = presses.filter { !Self.isBack($0) }
    if !rest.isEmpty { super.pressesChanged(rest, with: event) }
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    log("ended", presses)
    let rest = presses.filter { !Self.isBack($0) }
    if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    if rest.count != presses.count { onBack() }
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    let rest = presses.filter { !Self.isBack($0) }
    if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
  }

  /// Keyboards may deliver Escape as a key command rather than a press; claim it here so the
  /// presentation layer never sees it.
  override var keyCommands: [UIKeyCommand]? {
    [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapeKeyCommand))]
  }

  @objc private func escapeKeyCommand() {
    AppLog.player.notice("press escape-key-command")
    onBack()
  }

  private static func isBack(_ press: UIPress) -> Bool {
    press.type == .menu || press.key?.keyCode == .keyboardEscape
  }

  private func log(_ phase: String, _ presses: Set<UIPress>) {
    for press in presses where Self.isBack(press) {
      let key = press.key.map { "\($0.keyCode.rawValue)/\($0.charactersIgnoringModifiers)" } ?? "-"
      AppLog.player.notice("back press \(phase, privacy: .public) type=\(press.type.rawValue) key=\(key, privacy: .public)")
    }
  }
}
