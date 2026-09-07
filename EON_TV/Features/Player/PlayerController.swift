import AVFoundation
import Foundation
import Observation
import OSLog
import UIKit

enum AppLog {
  static let player = Logger(subsystem: "rumen.rusanov.EON-TV2", category: "player")
}

/// Drives one viewing session on the platform's streams.
///
/// EON serves live and timeshift playlists with no seekable window: the player can only play
/// forward from wherever a stream was requested. Every move in time therefore becomes a new
/// stream request at a wall-clock timestamp, and the controller keeps the playhead anchored to
/// wall-clock time so programmes, progress and "live" can be reasoned about consistently.
@Observable
final class PlayerController: NSObject {
  enum Phase: Equatable {
    /// Waiting for a stream. `obscuresVideo` is true for a first load or a channel change,
    /// where the previous picture would be wrong; same-channel moves keep the last frame.
    case loading(obscuresVideo: Bool)
    case playing
    case failed(String)

    var isLoading: Bool {
      if case .loading = self { return true }
      return false
    }
  }

  struct MediaOption: Identifiable, Equatable {
    let id: String
    let title: String
    let isSelected: Bool
    let option: AVMediaSelectionOption?

    static func == (lhs: MediaOption, rhs: MediaOption) -> Bool {
      lhs.id == rhs.id && lhs.isSelected == rhs.isSelected
    }
  }

  let player = AVPlayer()

  private(set) var channel: Channel
  private(set) var mode: PlaybackRequest.Mode
  private(set) var lineup: [Channel]
  private(set) var phase: Phase = .loading(obscuresVideo: true)
  private(set) var isPaused = false
  private(set) var isBuffering = false
  /// The programme the playhead is currently inside.
  private(set) var currentProgram: Schedule?
  /// A short notice shown over the video (e.g. "Back to live").
  private(set) var notice: String?
  private(set) var subtitleOptions: [MediaOption] = []
  private(set) var audioOptions: [MediaOption] = []

  let backend: Backend
  let store: ContentStore
  let history: WatchHistory
  let favorites: FavoritesStore
  let clock: LiveClock

  /// Seconds of live stream the player can safely resume from after a pause.
  static let pauseBufferSeconds: TimeInterval = 8
  /// Positions closer than this to now are treated as live.
  static let liveThresholdMs = 5_000

  // Wall-clock anchoring: the player time at which `anchorWallMs` was the real-world position.
  private var anchorPlayerSeconds: Double?
  private var anchorWallMs: Int = 0

  private var loadTask: Task<Void, Never>?
  private var noticeTask: Task<Void, Never>?
  private var itemObservations: [NSKeyValueObservation] = []
  private var notificationTokens: [NSObjectProtocol] = []
  private var timeObserver: Any?
  private var retryCount = 0
  private var hasStarted = false
  private var lastResumeSave: Date = .distantPast
  private var lastTimelineLog: Date = .distantPast
  private var pausedAtMs: Int?
  private var pausedAt: Date?
  private var nowPlaying: NowPlayingBridge?
  private var lastPlayPauseToggle: Date = .distantPast

  var isLive: Bool { if case .live = mode { return true } else { return false } }
  var isFavorite: Bool { favorites.contains(channel.id) }

  var hasFailed: Bool {
    if case .failed = phase { return true }
    return false
  }

  init(request: PlaybackRequest, backend: Backend, store: ContentStore, history: WatchHistory, favorites: FavoritesStore, clock: LiveClock) {
    self.channel = request.channel
    self.mode = request.mode
    self.lineup = request.lineup.isEmpty ? store.channels : request.lineup
    self.backend = backend
    self.store = store
    self.history = history
    self.favorites = favorites
    self.clock = clock
    super.init()
    // Apple TV never sends AirPlay Video anywhere; leaving the switch on only muddies audio routing.
    player.allowsExternalPlayback = false
    player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
      MainActor.assumeIsolated { self?.handleTimeControlChange(player) }
    }.store(in: &itemObservations)
  }

  // MARK: Lifecycle

  /// Begins playback of the initial request. Safe to call more than once.
  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    PlaybackAudioSession.retain()
    let bridge = NowPlayingBridge(
      player: player,
      onPlay: { [weak self] in self?.resume() },
      onPause: { [weak self] in self?.pause() },
      onTogglePlayPause: { [weak self] in self?.togglePlayPause() }
    )
    nowPlaying = bridge
    bridge.activate()
    installTimeObserver()
    load(channel: channel, mode: mode)
  }

  func stop() {
    saveResumePosition(force: true)
    loadTask?.cancel()
    noticeTask?.cancel()
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    detachItemObservers()
    itemObservations.removeAll()
    player.pause()
    player.replaceCurrentItem(with: nil)
    nowPlaying?.end()
    nowPlaying = nil
    if hasStarted {
      PlaybackAudioSession.release()
      hasStarted = false
    }
  }

  // MARK: Loading

  func load(channel: Channel, mode: PlaybackRequest.Mode) {
    saveResumePosition(force: true)
    loadTask?.cancel()
    let obscures = channel != self.channel || player.currentItem == nil || phase != .playing
    self.channel = channel
    self.mode = mode
    self.phase = .loading(obscuresVideo: obscures)
    self.currentProgram = mode.schedule ?? store.schedule(at: mode.requestedStartMs ?? clock.nowMs, channelID: channel.id) ?? store.nowPlaying(channel)
    anchorPlayerSeconds = nil
    pausedAtMs = nil
    pausedAt = nil
    isPaused = false
    retryCount = 0
    subtitleOptions = []
    audioOptions = []

    loadTask = Task { [weak self] in
      await self?.resolveAndPlay()
    }
  }

  private func resolveAndPlay() async {
    let channel = self.channel
    let mode = self.mode
    do {
      let startMs = mode.requestedStartMs
      let (url, resolvedStartMs, serverNowMs) = try await backend.streaming.getStreamingUrl(forChannel: channel, startTime: startMs)
      guard !Task.isCancelled, channel == self.channel, mode == self.mode else { return }

      AppLog.player.notice("loading stream host=\(url.host() ?? "?", privacy: .public) mode=\(String(describing: mode), privacy: .public)")
      anchorWallMs = startMs == nil ? serverNowMs : resolvedStartMs
      anchorPlayerSeconds = nil

      let item = AVPlayerItem(url: url)
      attachItemObservers(item)
      player.replaceCurrentItem(with: item)
      publishNowPlaying()
      player.play()
      history.recordChannel(channel.id)
      Task { await ensureGuideLoaded() }
    } catch {
      guard !Task.isCancelled else { return }
      AppLog.player.error("stream request failed: \(String(describing: error), privacy: .public)")
      phase = .failed(failureMessage(for: error))
    }
  }

  /// Retries the current request with a fresh stream session.
  func retry() {
    load(channel: channel, mode: mode)
  }

  // MARK: Actions

  func goLive() {
    guard !isLive else { return }
    show(notice: "Back to live")
    load(channel: channel, mode: .live)
  }

  func startOver() {
    guard let programme = currentProgram ?? store.nowPlaying(channel), channel.canStartOver else { return }
    show(notice: "From the start: \(programme.title)")
    load(channel: channel, mode: .startOver(programme))
  }

  /// Plays a programme from the panel: past programmes from the start, the current one from
  /// its start (start-over), upcoming ones are not playable.
  func play(_ schedule: Schedule) {
    let now = clock.nowMs
    if schedule.isAiring(at: now) {
      if channel.canStartOver {
        load(channel: channel, mode: .startOver(schedule))
      } else {
        load(channel: channel, mode: .live)
      }
    } else if schedule.hasEnded(at: now) {
      guard channel.isWithinCatchUpWindow(schedule, nowMs: now) else {
        show(notice: "\(schedule.title) is no longer available")
        return
      }
      load(channel: channel, mode: .catchUp(schedule, offsetMs: 0))
    }
  }

  /// Moves to an absolute wall-clock position. Near the live edge this returns to the live
  /// stream; otherwise it requests the timeshift stream at that instant.
  func seek(toWallClockMs target: Int) {
    let now = clock.nowMs
    if target >= now - Self.liveThresholdMs {
      if !isLive {
        show(notice: "Back to live")
        load(channel: channel, mode: .live)
      } else {
        player.play()
      }
      return
    }
    guard channel.canCatchUp else {
      show(notice: "\(channel.name) doesn't offer catch-up")
      return
    }
    let earliest = now - Int(channel.catchUpWindow * 1000)
    let clamped = max(target, earliest)
    load(channel: channel, mode: .timeshift(atMs: clamped))
  }

  func switchChannel(_ next: Channel) {
    guard next != channel else { return }
    load(channel: next, mode: .live)
  }

  func toggleFavorite() {
    favorites.toggle(channel)
  }

  /// Live TV pause: the stream has no buffer to speak of, so resuming after more than a few
  /// seconds re-requests the timeshift stream at the moment playback was paused.
  func togglePlayPause() {
    // The Siri Remote's play/pause reaches us both as a press and, once we are the Now Playing
    // player, as a remote command; a second toggle within a moment is the same press.
    let now = Date()
    guard now.timeIntervalSince(lastPlayPauseToggle) > 0.3 else { return }
    lastPlayPauseToggle = now
    if isPaused || player.rate == 0 {
      resume()
    } else {
      pause()
    }
  }

  func pause() {
    guard !isPaused else { return }
    pausedAtMs = playheadMs
    pausedAt = Date()
    player.pause()
    isPaused = true
  }

  func resume() {
    guard isPaused else {
      player.play()
      return
    }
    isPaused = false
    let gap = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
    if gap > Self.pauseBufferSeconds, let pausedAtMs {
      if channel.canCatchUp {
        show(notice: "Resuming where you paused")
        load(channel: channel, mode: .timeshift(atMs: pausedAtMs))
      } else {
        show(notice: "Live has moved on")
        load(channel: channel, mode: .live)
      }
    } else {
      player.play()
    }
    pausedAtMs = nil
    pausedAt = nil
  }

  var nextChannel: Channel? {
    guard let index = lineup.firstIndex(of: channel) else { return lineup.first }
    return lineup[(index + 1) % lineup.count]
  }

  var previousChannel: Channel? {
    guard let index = lineup.firstIndex(of: channel) else { return lineup.last }
    return lineup[(index - 1 + lineup.count) % lineup.count]
  }

  // MARK: Media options

  func select(_ option: MediaOption, in options: [MediaOption]) {
    guard let item = player.currentItem else { return }
    Task {
      let characteristic: AVMediaCharacteristic = options.first?.id.hasPrefix("audio") == true ? .audible : .legible
      guard let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic) else { return }
      item.select(option.option, in: group)
      await refreshMediaOptions()
    }
  }

  private func refreshMediaOptions() async {
    guard let item = player.currentItem else { return }
    let asset = item.asset
    var subtitles: [MediaOption] = []
    if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
      let selected = item.currentMediaSelection.selectedMediaOption(in: group)
      subtitles.append(MediaOption(id: "subtitle-off", title: "Off", isSelected: selected == nil, option: nil))
      for option in group.options where !option.hasMediaCharacteristic(.containsOnlyForcedSubtitles) {
        subtitles.append(MediaOption(id: "subtitle-\(option.displayName)-\(option.locale?.identifier ?? "")", title: option.displayName, isSelected: option == selected, option: option))
      }
      if subtitles.count == 1 { subtitles = [] }
    }
    var audio: [MediaOption] = []
    if let group = try? await asset.loadMediaSelectionGroup(for: .audible), group.options.count > 1 {
      let selected = item.currentMediaSelection.selectedMediaOption(in: group)
      audio = group.options.map {
        MediaOption(id: "audio-\($0.displayName)-\($0.locale?.identifier ?? "")", title: $0.displayName, isSelected: $0 == selected, option: $0)
      }
    }
    guard item == player.currentItem else { return }
    subtitleOptions = subtitles
    audioOptions = audio
  }

  var hasMediaOptions: Bool { !subtitleOptions.isEmpty || !audioOptions.isEmpty }

  // MARK: Playhead → programme

  /// Real-world time the playhead currently corresponds to, in epoch milliseconds.
  var playheadMs: Int? {
    guard let anchor = anchorPlayerSeconds else { return nil }
    let seconds = player.currentTime().seconds
    guard seconds.isFinite else { return nil }
    return anchorWallMs + Int((seconds - anchor) * 1000)
  }

  /// How far behind the live edge the viewer is, in milliseconds (0 when live).
  var behindLiveMs: Int {
    guard !isLive, let playhead = playheadMs else { return 0 }
    return max(0, clock.nowMs - playhead)
  }

  private func installTimeObserver() {
    guard timeObserver == nil else { return }
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 10), queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tick()
      }
    }
  }

  /// Bumps observers every half second so timeline views can redraw from the playhead.
  private(set) var timelinePulse = 0

  private func tick() {
    logTimelineIfDue()
    guard phase == .playing else { return }
    if anchorPlayerSeconds == nil, player.currentItem?.status == .readyToPlay {
      let seconds = player.currentTime().seconds
      if seconds.isFinite { anchorPlayerSeconds = seconds }
    }
    timelinePulse &+= 1
    guard let playhead = playheadMs else { return }

    if let programme = store.schedule(at: playhead, channelID: channel.id) {
      if programme != currentProgram {
        currentProgram = programme
        publishNowPlaying()
      }
    } else if store.epgState(for: channel.id, day: playhead.dateFromMs) == .idle {
      Task { await store.ensureEPG(day: playhead.dateFromMs, for: [channel]) }
    }
    saveResumePosition(force: false)
  }

  private func saveResumePosition(force: Bool) {
    guard !isLive, let playhead = playheadMs, let programme = currentProgram else { return }
    guard force || Date().timeIntervalSince(lastResumeSave) > 10 else { return }
    lastResumeSave = Date()
    history.updateResume(for: programme, positionMs: playhead - programme.startTime)
  }

  private func ensureGuideLoaded() async {
    await store.ensureEPG(day: clock.dayStart, for: [channel])
    if let requested = mode.requestedStartMs {
      await store.ensureEPG(day: requested.dateFromMs, for: [channel])
    }
    if currentProgram == nil {
      currentProgram = store.schedule(at: mode.requestedStartMs ?? clock.nowMs, channelID: channel.id) ?? store.nowPlaying(channel)
      publishNowPlaying()
    }
  }

  // MARK: Now Playing

  /// Hands the current programme and channel to the system's Now Playing information.
  private func publishNowPlaying() {
    nowPlaying?.update(
      item: player.currentItem,
      title: currentProgram?.title ?? channel.name,
      subtitle: currentProgram == nil ? nil : channel.name
    )
  }

  // MARK: Item observation & recovery

  private func attachItemObservers(_ item: AVPlayerItem) {
    detachItemObservers()
    notificationTokens.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
      let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
      MainActor.assumeIsolated { self?.handleFailure(error) }
    })
    notificationTokens.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        AppLog.player.notice("item played to end")
        self?.handleEnded()
      }
    })
    notificationTokens.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        AppLog.player.notice("playback stalled at \(self?.player.currentTime().seconds ?? -1)")
        if self?.isPaused == false { self?.player.play() }
      }
    })
    item.observe(\.status, options: [.new]) { [weak self] item, _ in
      MainActor.assumeIsolated { self?.handleStatus(item) }
    }.store(in: &itemObservations)
  }

  private func detachItemObservers() {
    notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    notificationTokens.removeAll()
    // Keep the player-level observation (first entry); drop item-level ones.
    if itemObservations.count > 1 {
      itemObservations.removeSubrange(1...)
    }
  }

  private func handleTimeControlChange(_ player: AVPlayer) {
    AppLog.player.notice("timeControl=\(player.timeControlStatus.rawValue) waiting=\(player.reasonForWaitingToPlay?.rawValue ?? "-", privacy: .public) rate=\(player.rate)")
    isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate && phase == .playing
  }

  private func handleStatus(_ item: AVPlayerItem) {
    AppLog.player.notice("item status=\(item.status.rawValue) error=\(String(describing: item.error), privacy: .public)")
    switch item.status {
    case .readyToPlay:
      retryCount = 0
      phase = .playing
      AppLog.audio.notice("item ready; \(PlaybackAudioSession.routeDescription(), privacy: .public)")
      let seconds = player.currentTime().seconds
      if seconds.isFinite { anchorPlayerSeconds = seconds }
      Task { await refreshMediaOptions() }
    case .failed:
      handleFailure(item.error)
    default:
      break
    }
  }

  private func handleFailure(_ error: Error?) {
    let detail = player.currentItem?.errorLog()?.events.last.map { "\($0.errorStatusCode) \($0.errorComment ?? "")" } ?? "-"
    AppLog.player.error("playback failure attempt=\(self.retryCount) itemStatus=\(self.player.currentItem?.status.rawValue ?? -1) error=\(error.map { String(describing: $0) } ?? "nil", privacy: .public) log=\(detail, privacy: .public)")

    // A mid-stream hiccup on an item that is still healthy: nudge playback rather than
    // tearing the stream down, so the picture never drops to black.
    if let item = player.currentItem, item.status == .readyToPlay, retryCount == 0 {
      retryCount += 1
      if !isPaused { player.play() }
      return
    }

    if retryCount < 3 {
      retryCount += 1
      let attempt = retryCount
      phase = .loading(obscuresVideo: false)
      show(notice: "Reconnecting…")
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(Double(attempt)))
        guard let self, self.phase.isLoading, self.retryCount == attempt else { return }
        await self.resolveAndPlay()
      }
      return
    }
    phase = .failed(failureMessage(for: error))
  }

  private func handleEnded() {
    // A timeshift stream that reaches its end has nothing more to give: return to live.
    if !isLive {
      goLive()
    }
  }

  private func failureMessage(for error: Error?) -> String {
    if channel.drmRequired {
      return "\(channel.name) uses protected content that this app can't play yet."
    }
    if let error {
      return ErrorPresenter.message(for: error, context: .playback)
    }
    return "Playback stopped unexpectedly. Please try again."
  }

  // MARK: Diagnostics

  /// Periodic notice-level snapshot of the item's timeline so behaviour on real streams can be
  /// read back from the unified log.
  private func logTimelineIfDue() {
    guard Date().timeIntervalSince(lastTimelineLog) > 10, let item = player.currentItem else { return }
    lastTimelineLog = Date()
    let seekable = item.seekableTimeRanges.map { $0.timeRangeValue }.map { "\(Int($0.start.seconds))-\(Int(CMTimeRangeGetEnd($0).seconds))" }.joined(separator: ",")
    let loaded = item.loadedTimeRanges.map { $0.timeRangeValue }.map { "\(Int($0.start.seconds))-\(Int(CMTimeRangeGetEnd($0).seconds))" }.joined(separator: ",")
    AppLog.player.notice("timeline current=\(Int(self.player.currentTime().seconds)) seekable=[\(seekable, privacy: .public)] loaded=[\(loaded, privacy: .public)] rate=\(self.player.rate) playhead=\(self.playheadMs ?? -1) live=\(self.isLive)")
  }

  // MARK: Notices

  func show(notice text: String) {
    notice = text
    noticeTask?.cancel()
    noticeTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2.5))
      guard !Task.isCancelled else { return }
      self?.notice = nil
    }
  }
}

private extension NSKeyValueObservation {
  func store(in array: inout [NSKeyValueObservation]) {
    array.append(self)
  }
}
