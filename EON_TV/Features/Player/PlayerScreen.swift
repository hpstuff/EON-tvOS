import AVFoundation
import OSLog
import SwiftUI

/// The player as presented. A UIKit press interceptor wraps the SwiftUI screen so Back is
/// always ours to interpret, whatever kind of remote or keyboard sent it.
struct PlayerScreen: View {
  let request: PlaybackRequest
  @State private var back = BackRelay()
  @State private var scrub = ScrubRelay()

  var body: some View {
    BackInterceptingHost(onBack: { back.fire() }, onScrub: { scrub.post($0) }) {
      PlayerScreenContent(request: request, back: back, scrub: scrub)
    }
    .ignoresSafeArea()
  }
}

/// Full-screen playback with controls designed for live television on this platform.
///
/// The streams cannot be scrubbed, so the timeline is programme-based: it shows where the
/// viewer is inside the current programme relative to the live edge, and every move (skip,
/// pause-resume, start over) becomes a fresh timeshift request at a wall-clock instant.
///
/// Remote model
/// - Controls hidden: select shows controls · play/pause toggles · left/right skip a fixed step
///   (preview, then commit) · a touchpad slide scrubs · down opens the schedule · up opens
///   channels · Back leaves the player.
/// - Controls visible: the timeline has focus; left/right skip, a slide scrubs, down reaches the
///   buttons, Back cancels a pending skip, then hides the controls.
struct PlayerScreenContent: View {
  let request: PlaybackRequest
  let back: BackRelay
  let scrub: ScrubRelay

  @Environment(AppSession.self) private var session
  @Environment(ContentStore.self) private var store
  @Environment(WatchHistory.self) private var history
  @Environment(FavoritesStore.self) private var favorites
  @Environment(LiveClock.self) private var clock
  @Environment(PlaybackCoordinator.self) private var coordinator

  @State private var controller: PlayerController?
  @State private var controlsVisible = false
  @State private var panel: Panel = .none
  @State private var previewMs: Int?
  /// Where a touchpad slide started, and how long that programme is; nil when not scrubbing.
  @State private var scrubAnchorMs: Int?
  @State private var scrubAnchorDurationMs = 1_800_000
  @State private var lastScrubEnded: Date = .distantPast
  @State private var hideTask: Task<Void, Never>?
  @State private var commitTask: Task<Void, Never>?
  @State private var autoHiddenAt: Date?
  @FocusState private var focus: PlayerFocus?

  enum Panel: Equatable {
    case none, schedule, channels, options
  }

  enum ControlButton: Hashable {
    case playPause, timeshift, schedule, channels, options, favorite
  }

  enum PlayerFocus: Hashable {
    case surface
    case timeline
    case button(ControlButton)
    case failureRetry, failureLive, failureClose
    case panelItem(String)
  }

  private static let hideDelay: Duration = .seconds(7)
  /// A Back pressed this soon after the controls auto-hid was meant for the controls, not the player.
  private static let exitGrace: TimeInterval = 3.0
  private static let commitDelay: Duration = .milliseconds(900)
  /// Each left/right press moves this far.
  private static let nudgeSeconds = 15
  /// A slide across the whole touchpad travels this much of the programme it started in.
  private static let swipeProgrammeFraction = 1.0 / 5.0

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if let controller {
        PlayerLayerView(player: controller.player)
          .ignoresSafeArea()

        loadingOverlay(controller)

        if controller.hasFailed {
          if case .failed(let message) = controller.phase {
            failureView(controller, message: message)
          }
        } else {
          switch panel {
          case .none:
            if controlsVisible {
              controls(controller)
            } else {
              hiddenSurface(controller)
            }
          case .schedule:
            SchedulePanel(controller: controller, focus: $focus, onClose: closePanel)
          case .channels:
            ChannelsPanel(controller: controller, focus: $focus, onClose: closePanel)
          case .options:
            MediaOptionsPanel(controller: controller, focus: $focus, onClose: closePanel)
          }
          noticeOverlay(controller)
        }
      }
    }
    .onExitCommand { back.fire() }
    .onChange(of: back.count) { _, _ in handleExit() }
    .onChange(of: scrub.count) { _, _ in handleScrub(scrub.event) }
    .onPlayPauseCommand(perform: handlePlayPause)
    .onAppear(perform: makeController)
    .onDisappear { controller?.stop() }
    .onChange(of: request.id) { _, _ in
      controller?.load(channel: request.channel, mode: request.mode)
    }
    .onChange(of: focus) { _, newValue in
      AppLog.player.notice("focus=\(String(describing: newValue), privacy: .public) controls=\(controlsVisible) panel=\(String(describing: panel), privacy: .public)")
      scheduleAutoHide()
      if newValue == nil { reseatFocus() }
    }
    .onChange(of: controller?.isPaused ?? false) { _, paused in
      if paused { showControls(focusTimeline: false) } else { scheduleAutoHide() }
    }
  }

  private func makeController() {
    guard controller == nil, let backend = session.backend else { return }
    let created = PlayerController(
      request: request,
      backend: backend,
      store: store,
      history: history,
      favorites: favorites,
      clock: clock
    )
    controller = created
    created.start()
    focus = .surface
  }

  private func close() {
    AppLog.player.notice("player closing")
    coordinator.dismissPlayer()
  }

  // MARK: Hidden state

  /// Invisible full-screen control that owns focus while the controls are hidden.
  private func hiddenSurface(_ controller: PlayerController) -> some View {
    Button {
      showControls(focusTimeline: true)
    } label: {
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(.bare)
    .focused($focus, equals: .surface)
    .defaultFocus($focus, .surface)
    .onAppear { focus = .surface }
    .onMoveCommand { direction in
      switch direction {
      case .left: showControls(focusTimeline: true); nudge(-1, controller)
      case .right: showControls(focusTimeline: true); nudge(+1, controller)
      case .down: openPanel(.schedule)
      case .up: openPanel(.channels)
      @unknown default: break
      }
    }
  }

  // MARK: Controls

  private func controls(_ controller: PlayerController) -> some View {
    let now = clock.nowMs
    let playhead = controller.playheadMs ?? now
    let displayedMs = previewMs ?? playhead
    let programme = store.schedule(at: displayedMs, channelID: controller.channel.id) ?? controller.currentProgram

    return VStack {
      HStack(alignment: .top) {
        Spacer()
        Text(clock.now.shortTime)
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(.white.opacity(0.85))
          .padding(.horizontal, 18)
          .padding(.vertical, 8)
          .background(Capsule().fill(Color.black.opacity(0.45)))
      }
      .padding(.top, 50)
      .padding(.horizontal, Theme.screenMargin)

      Spacer()

      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 14) {
          ChannelLogo(channel: controller.channel, height: 40, platter: false)
          Text(controller.channel.name)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
          Text("· Channel \(store.channelNumber(controller.channel))")
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
          Spacer()
          statusBadge(controller, displayedMs: displayedMs, now: now)
        }

        Text(programme?.title ?? controller.channel.name)
          .font(.system(size: 44, weight: .regular))
          .foregroundStyle(.white)
          .lineLimit(1)

        if let programme {
          HStack(spacing: 14) {
            Text(programme.timeRangeText)
              .font(.system(size: 24, weight: .medium))
              .foregroundStyle(.white.opacity(0.7))
            if let subtitle = programme.subtitleText {
              Text(subtitle)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            }
          }
        }

        timeline(controller, programme: programme, playheadMs: playhead, now: now)

        buttons(controller)
      }
      .padding(.horizontal, Theme.screenMargin)
      .padding(.bottom, 56)
      .padding(.top, 120)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: .black.opacity(0.55), location: 0.35),
            .init(color: .black.opacity(0.88), location: 1),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        .ignoresSafeArea()
      }
    }
    .transition(.opacity)
  }

  @ViewBuilder
  private func statusBadge(_ controller: PlayerController, displayedMs: Int, now: Int) -> some View {
    if controller.isPaused {
      Tag(text: "PAUSED")
    } else if previewMs != nil {
      Tag(text: "SKIPPING", solid: true)
    } else if controller.isLive {
      LiveBadge()
    } else {
      let behind = max(0, now - displayedMs)
      if behind < 3_600_000 {
        Tag(text: "\(max(1, behind / 60_000)) MIN BEHIND LIVE", solid: true)
      } else {
        Tag(text: "CATCH UP")
      }
    }
  }

  // MARK: Timeline

  private func timeline(_ controller: PlayerController, programme: Schedule?, playheadMs: Int, now: Int) -> some View {
    Button {
      if previewMs != nil {
        commitPreview(controller)
      } else {
        controller.togglePlayPause()
      }
      scheduleAutoHide()
    } label: {
      ProgrammeTimeline(
        programme: programme,
        playheadMs: playheadMs,
        previewMs: previewMs,
        nowMs: now,
        isLive: controller.isLive,
        pulse: controller.timelinePulse
      )
    }
    .buttonStyle(.bare)
    .focused($focus, equals: .timeline)
    .onMoveCommand { direction in
      switch direction {
      case .left: nudge(-1, controller)
      case .right: nudge(+1, controller)
      case .down: focus = .button(.playPause)
      case .up: break
      @unknown default: break
      }
    }
  }

  // MARK: Buttons

  /// The row keeps a stable set of identities: Start Over and Go Live share one button, and the
  /// options button is always present, so a press never removes the control that has focus.
  private func buttons(_ controller: PlayerController) -> some View {
    HStack(spacing: 16) {
      controlButton(.playPause, title: controller.isPaused ? "Play" : "Pause", symbol: controller.isPaused ? "play.fill" : "pause.fill") {
        controller.togglePlayPause()
      }
      if let timeshift = timeshiftAction(controller) {
        controlButton(.timeshift, title: timeshift.title, symbol: timeshift.symbol, action: timeshift.action)
      }
      controlButton(.schedule, title: "Schedule", symbol: "list.bullet.rectangle") {
        openPanel(.schedule)
      }
      controlButton(.channels, title: "Channels", symbol: "tv") {
        openPanel(.channels)
      }
      controlButton(.options, title: "Audio & Subtitles", symbol: "captions.bubble") {
        openPanel(.options)
      }
      controlButton(.favorite, title: controller.isFavorite ? "Favorite" : "Add Favorite", symbol: controller.isFavorite ? "heart.fill" : "heart") {
        controller.toggleFavorite()
      }
      Spacer()
    }
  }

  /// One view identity for both timeshift states so focus survives switching between them.
  private func timeshiftAction(_ controller: PlayerController) -> (title: String, symbol: String, action: () -> Void)? {
    if controller.isLive {
      guard controller.channel.canStartOver else { return nil }
      return ("Start Over", "backward.end.fill", { controller.startOver() })
    }
    return ("Go Live", "dot.radiowaves.left.and.right", { controller.goLive() })
  }

  private func controlButton(_ id: ControlButton, title: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button {
      action()
      scheduleAutoHide()
    } label: {
      Label(title, systemImage: symbol)
    }
    .buttonStyle(.pill)
    .focused($focus, equals: .button(id))
  }

  // MARK: Overlays

  @ViewBuilder
  private func loadingOverlay(_ controller: PlayerController) -> some View {
    if case .loading(let obscures) = controller.phase, obscures {
      ZStack {
        Color.black.opacity(0.85)
        VStack(spacing: 26) {
          ChannelLogo(channel: controller.channel, height: 110, platter: false)
          VStack(spacing: 8) {
            Text(controller.currentProgram?.title ?? controller.channel.name)
              .font(.system(size: 40, weight: .regular))
              .foregroundStyle(.white)
              .lineLimit(1)
            Text(loadingSubtitle(controller))
              .font(.system(size: 26, weight: .medium))
              .foregroundStyle(Theme.textSecondary)
          }
          SpectrumLoadingLine()
            .frame(width: 360)
            .padding(.top, 8)
        }
      }
      .ignoresSafeArea()
      .transition(.opacity)
      .allowsHitTesting(false)
    } else if controller.phase.isLoading || controller.isBuffering {
      VStack {
        HStack {
          Spacer()
          ProgressView()
            .tint(.white)
            .scaleEffect(1.2)
            .padding(22)
            .background(Circle().fill(Color.black.opacity(0.5)))
            .padding(.top, 50)
            .padding(.trailing, Theme.screenMargin)
        }
        Spacer()
      }
      .transition(.opacity)
      .allowsHitTesting(false)
    }
  }

  private func loadingSubtitle(_ controller: PlayerController) -> String {
    switch controller.mode {
    case .live: return "\(controller.channel.name) · Live"
    case .startOver: return "\(controller.channel.name) · From the start"
    case .catchUp, .timeshift: return "\(controller.channel.name) · Catch Up"
    }
  }

  @ViewBuilder
  private func noticeOverlay(_ controller: PlayerController) -> some View {
    if let notice = controller.notice {
      VStack {
        Text(notice)
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 28)
          .padding(.vertical, 14)
          .background(Capsule().fill(Color.black.opacity(0.65)))
          .padding(.top, 60)
        Spacer()
      }
      .transition(.opacity.combined(with: .move(edge: .top)))
      .allowsHitTesting(false)
      .animation(.easeInOut(duration: 0.3), value: notice)
    }
  }

  private func failureView(_ controller: PlayerController, message: String) -> some View {
    ZStack {
      AmbientBackdrop(url: controller.currentProgram?.posterURL ?? controller.channel.logoURL, intensity: 0.4)
      VStack(spacing: 28) {
        ChannelLogo(channel: controller.channel, height: 90, platter: false)
        Text("Can't play \(controller.channel.name)")
          .font(.system(size: 42, weight: .regular))
          .foregroundStyle(.white)
        Text(message)
          .font(.system(size: 26))
          .foregroundStyle(Theme.textSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 820)
        HStack(spacing: 20) {
          Button { controller.retry() } label: {
            Label("Try Again", systemImage: "arrow.clockwise")
          }
          .buttonStyle(.prominentPill)
          .focused($focus, equals: .failureRetry)

          if !controller.isLive {
            Button { controller.goLive() } label: {
              Label("Watch Live Instead", systemImage: "play.fill")
            }
            .buttonStyle(.pill)
            .focused($focus, equals: .failureLive)
          }

          Button(action: close) {
            Label("Close", systemImage: "xmark")
          }
          .buttonStyle(.pill)
          .focused($focus, equals: .failureClose)
        }
        .padding(.top, 10)
      }
    }
    .transition(.opacity)
    .onAppear { focus = .failureRetry }
  }

  // MARK: Behaviour

  /// Back works the same wherever focus happens to be: close a panel, cancel a pending skip,
  /// hide the controls, and only then leave the player.
  private func handleExit() {
    AppLog.player.notice("exit pressed controls=\(controlsVisible) panel=\(String(describing: panel), privacy: .public) preview=\(previewMs ?? -1) focus=\(String(describing: focus), privacy: .public)")
    guard let controller, !controller.hasFailed else {
      close()
      return
    }
    if panel != .none {
      closePanel()
    } else if controlsVisible {
      if previewMs != nil {
        cancelPreview()
        scheduleAutoHide()
      } else {
        hideControls()
      }
    } else if let autoHiddenAt, Date().timeIntervalSince(autoHiddenAt) < Self.exitGrace {
      // The controls vanished a moment ago on their own; this press was for them.
      self.autoHiddenAt = nil
    } else {
      close()
    }
  }

  /// Focus must never be nowhere: an unhandled Back would dismiss the whole player. If nothing
  /// holds focus a moment after a change, put it back on the right element for the state.
  private func reseatFocus() {
    Task {
      try? await Task.sleep(for: .milliseconds(150))
      guard focus == nil, let controller, !controller.hasFailed else { return }
      switch panel {
      case .none:
        focus = controlsVisible ? .timeline : .surface
      case .schedule, .channels, .options:
        break
      }
    }
  }

  private func handlePlayPause() {
    guard let controller, !controller.hasFailed, panel == .none else { return }
    if previewMs != nil {
      commitPreview(controller)
    } else {
      controller.togglePlayPause()
    }
    scheduleAutoHide()
  }

  private func showControls(focusTimeline: Bool) {
    let wasHidden = !controlsVisible
    withAnimation(.easeOut(duration: 0.2)) { controlsVisible = true }
    if focusTimeline || wasHidden || focus == .surface || focus == nil {
      // The timeline joins the hierarchy on the next update; focus it once it exists.
      Task {
        try? await Task.sleep(for: .milliseconds(60))
        if controlsVisible, panel == .none { focus = .timeline }
      }
    }
    scheduleAutoHide()
  }

  private func hideControls(automatic: Bool = false) {
    cancelPreview()
    autoHiddenAt = automatic ? Date() : nil
    withAnimation(.easeIn(duration: 0.25)) { controlsVisible = false }
    focus = .surface
  }

  private func scheduleAutoHide() {
    hideTask?.cancel()
    guard controlsVisible, panel == .none else { return }
    hideTask = Task {
      try? await Task.sleep(for: Self.hideDelay)
      guard !Task.isCancelled, let controller else { return }
      guard controlsVisible, panel == .none, previewMs == nil, !controller.isPaused else { return }
      hideControls(automatic: true)
    }
  }

  private func openPanel(_ target: Panel) {
    hideTask?.cancel()
    cancelPreview()
    withAnimation(.easeOut(duration: 0.25)) {
      controlsVisible = false
      panel = target
    }
  }

  private func closePanel() {
    withAnimation(.easeIn(duration: 0.2)) { panel = .none }
    showControls(focusTimeline: true)
  }

  /// Skips by a fixed step per press; the move is previewed on the timeline and committed after
  /// a short pause, or immediately with select or play/pause.
  private func nudge(_ direction: Int, _ controller: PlayerController) {
    // A touchpad slide also surfaces as move commands; the slide already moved the preview.
    guard scrubAnchorMs == nil, Date().timeIntervalSince(lastScrubEnded) > 0.3 else { return }
    let now = clock.nowMs
    guard controller.channel.canCatchUp || direction > 0 else {
      controller.show(notice: "\(controller.channel.name) doesn't offer catch-up")
      return
    }
    let base = previewMs ?? controller.playheadMs ?? now
    previewMs = clampedTarget(base + direction * Self.nudgeSeconds * 1000, controller)
    scheduleAutoHide()
    scheduleCommit(controller)
  }

  /// Continuous scrubbing from the touchpad: the slide is anchored where it began, one full
  /// width travels a fifth of that programme, and the result is committed once the finger lifts.
  private func handleScrub(_ event: ScrubRelay.Event) {
    guard let controller, !controller.hasFailed, panel == .none else { return }
    switch event {
    case .began:
      guard focus == .surface || focus == .timeline || focus == nil else { return }
      guard controller.channel.canCatchUp else {
        controller.show(notice: "\(controller.channel.name) doesn't offer catch-up")
        return
      }
      commitTask?.cancel()
      let anchor = previewMs ?? controller.playheadMs ?? clock.nowMs
      let programme = store.schedule(at: anchor, channelID: controller.channel.id) ?? controller.currentProgram
      scrubAnchorMs = anchor
      scrubAnchorDurationMs = max(60_000, programme.map { $0.endTime - $0.startTime } ?? 1_800_000)
      previewMs = clampedTarget(anchor, controller)
      showControls(focusTimeline: true)
    case .moved(let fraction):
      guard let anchor = scrubAnchorMs else { return }
      let delta = Int(fraction * Double(scrubAnchorDurationMs) * Self.swipeProgrammeFraction)
      previewMs = clampedTarget(anchor + delta, controller)
    case .ended:
      guard scrubAnchorMs != nil else { return }
      scrubAnchorMs = nil
      lastScrubEnded = Date()
      scheduleAutoHide()
      scheduleCommit(controller)
    }
  }

  /// Keeps a target inside the catch-up window and never ahead of live.
  private func clampedTarget(_ ms: Int, _ controller: PlayerController) -> Int {
    let now = clock.nowMs
    let earliest = now - Int(controller.channel.catchUpWindow * 1000)
    return min(now, max(earliest, ms))
  }

  private func scheduleCommit(_ controller: PlayerController) {
    commitTask?.cancel()
    commitTask = Task {
      try? await Task.sleep(for: Self.commitDelay)
      guard !Task.isCancelled else { return }
      commitPreview(controller)
    }
  }

  private func commitPreview(_ controller: PlayerController) {
    commitTask?.cancel()
    guard let target = previewMs else { return }
    previewMs = nil
    controller.seek(toWallClockMs: target)
    scheduleAutoHide()
  }

  private func cancelPreview() {
    commitTask?.cancel()
    previewMs = nil
    scrubAnchorMs = nil
  }
}

// MARK: - Timeline

/// Programme-relative timeline: progress inside the programme, the live edge, and a ghost
/// marker while a skip is being previewed.
struct ProgrammeTimeline: View {
  let programme: Schedule?
  let playheadMs: Int
  let previewMs: Int?
  let nowMs: Int
  let isLive: Bool
  let pulse: Int

  @Environment(\.isFocused) private var isFocused

  var body: some View {
    let start = programme?.startTime ?? (playheadMs - 1_800_000)
    let end = programme?.endTime ?? (playheadMs + 1_800_000)
    let duration = max(1, end - start)
    let playFraction = fraction(playheadMs, start: start, duration: duration)
    let liveFraction = fraction(nowMs, start: start, duration: duration)
    let previewFraction = previewMs.map { fraction($0, start: start, duration: duration) }

    VStack(spacing: 10) {
      GeometryReader { proxy in
        let width = proxy.size.width
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(height: isFocused ? 12 : 8)

          if !isLive, nowMs > start, nowMs < end {
            Capsule()
              .fill(Color.white.opacity(0.10))
              .frame(width: width * liveFraction, height: isFocused ? 12 : 8)
          }

          Capsule()
            .fill(Theme.spectrum)
            .frame(width: width, height: isFocused ? 12 : 8)
            .mask(alignment: .leading) {
              Capsule().frame(width: max(6, width * (previewFraction ?? playFraction)))
            }

          if !isLive, nowMs > start, nowMs < end {
            VStack(spacing: 3) {
              Text("LIVE")
                .font(.system(size: 16, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(Theme.textOnFocus)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white))
              Rectangle()
                .fill(.white)
                .frame(width: 3, height: 20)
            }
            .position(x: width * liveFraction, y: proxy.size.height / 2 - 14)
          }

          Circle()
            .fill(.white)
            .frame(width: isFocused ? 26 : 18, height: isFocused ? 26 : 18)
            .shadow(color: .black.opacity(0.5), radius: 6)
            .position(x: width * (previewFraction ?? playFraction), y: proxy.size.height / 2)

          if let previewFraction, let previewMs {
            Text(previewMs.dateFromMs.shortTime)
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(Theme.textOnFocus)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(Capsule().fill(.white))
              .position(x: min(max(40, width * previewFraction), width - 40), y: -22)
          }
        }
        .frame(height: proxy.size.height)
      }
      .frame(height: 30)

      HStack {
        Text(start.dateFromMs.shortTime)
        Spacer()
        if previewMs == nil {
          Text(playheadMs.dateFromMs.shortTime)
            .foregroundStyle(.white.opacity(isFocused ? 1 : 0.7))
        }
        Spacer()
        Text(end.dateFromMs.shortTime)
      }
      .font(.system(size: 22, weight: .medium).monospacedDigit())
      .foregroundStyle(.white.opacity(0.7))
    }
    .padding(.top, 26)
    .animation(.easeOut(duration: 0.2), value: isFocused)
    .animation(.linear(duration: 0.4), value: pulse)
  }

  private func fraction(_ ms: Int, start: Int, duration: Int) -> CGFloat {
    CGFloat(min(1, max(0, Double(ms - start) / Double(duration))))
  }
}

// MARK: - Video layer

struct PlayerLayerView: UIViewRepresentable {
  let player: AVPlayer

  func makeUIView(context: Context) -> PlayerLayerHostView {
    let view = PlayerLayerHostView()
    view.playerLayer.player = player
    return view
  }

  func updateUIView(_ uiView: PlayerLayerHostView, context: Context) {
    if uiView.playerLayer.player !== player {
      uiView.playerLayer.player = player
    }
  }
}

final class PlayerLayerHostView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    playerLayer.videoGravity = .resizeAspect
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("unsupported") }
}
