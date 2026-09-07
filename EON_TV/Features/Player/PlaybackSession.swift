import AVFoundation
import AVKit
import MediaPlayer
import OSLog

extension AppLog {
  static let audio = Logger(subsystem: "rumen.rusanov.EON-TV2", category: "audio")
}

/// The shared audio session, configured the way tvOS expects from a long-form video app.
///
/// Apple TV keeps two tiers of output. HomePods used as the default output receive everything
/// the device plays, while AirPlay 2 speakers chosen in Control Center only receive audio the
/// system recognises as media playback. A session left at its SoloAmbient default is treated
/// like a game's, so its sound never reaches those speakers. AVPlayerViewController performs
/// this setup (and registers as the Now Playing player, see `NowPlayingBridge`) only while its
/// own controls are shown, which is why a custom player has to do it explicitly.
enum PlaybackAudioSession {
  private static var isConfigured = false
  private static var activePlayers = 0
  private static var routeToken: NSObjectProtocol?

  /// Applies the category once per process. Must run before the first `play()`.
  static func configure() {
    guard !isConfigured else { return }
    isConfigured = true
    let session = AVAudioSession.sharedInstance()
    do {
      // Long-form policies accept only the playback category, a movie/default/spoken mode and no options.
      try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormAudio, options: [])
      AppLog.audio.notice("audio session configured: playback/moviePlayback/longFormAudio")
    } catch {
      AppLog.audio.error("long-form audio policy rejected: \(String(describing: error), privacy: .public)")
      do {
        try session.setCategory(.playback, mode: .moviePlayback, policy: .default, options: [])
        AppLog.audio.notice("audio session configured: playback/moviePlayback/default")
      } catch {
        AppLog.audio.error("audio session category rejected: \(String(describing: error), privacy: .public)")
      }
    }
    observeRouteChanges()
  }

  /// Activates the session for a player that is about to start. Balanced by `release()`.
  static func retain() {
    configure()
    activePlayers += 1
    guard activePlayers == 1 else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      AppLog.audio.error("audio session activation failed: \(String(describing: error), privacy: .public)")
    }
    AppLog.audio.notice("playback starting; \(routeDescription(), privacy: .public)")
  }

  /// Lets other apps' audio resume once the last player has stopped.
  static func release() {
    activePlayers = max(0, activePlayers - 1)
    guard activePlayers == 0 else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      AppLog.audio.error("audio session deactivation failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// One line describing where the session's audio currently goes, for the unified log.
  static func routeDescription() -> String {
    let session = AVAudioSession.sharedInstance()
    let outputs = session.currentRoute.outputs
      .map { "\($0.portType.rawValue)/\($0.portName)" }
      .joined(separator: ", ")
    return "outputs=[\(outputs)] category=\(session.category.rawValue) mode=\(session.mode.rawValue) policy=\(session.routeSharingPolicy.rawValue) latency=\(Int(session.outputLatency * 1000))ms"
  }

  private static func observeRouteChanges() {
    guard routeToken == nil else { return }
    routeToken = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
      let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
      AppLog.audio.notice("route changed reason=\(reason) \(routeDescription(), privacy: .public)")
    }
  }
}

/// Registers the player as the app's Now Playing player, as AVPlayerViewController does while
/// its transport controls are visible.
///
/// Being the Now Playing player is what makes Control Center, Siri and the AirPlay 2 speaker
/// group treat the app's output as media playback rather than incidental sound. Now Playing
/// information (title, elapsed time, live state) is published automatically from the player;
/// the current programme and channel are supplied through the item's external metadata.
final class NowPlayingBridge {
  private let session: MPNowPlayingSession
  private var targets: [(MPRemoteCommand, Any)] = []

  init(player: AVPlayer, onPlay: @escaping () -> Void, onPause: @escaping () -> Void, onTogglePlayPause: @escaping () -> Void) {
    session = MPNowPlayingSession(players: [player])
    session.automaticallyPublishesNowPlayingInfo = true

    let center = session.remoteCommandCenter
    register(center.playCommand, onPlay)
    register(center.pauseCommand, onPause)
    register(center.togglePlayPauseCommand, onTogglePlayPause)
    // Live television has no tracks or in-stream scrubbing; keep those controls off the Now Playing UI.
    for command in [
      center.nextTrackCommand, center.previousTrackCommand,
      center.skipForwardCommand, center.skipBackwardCommand,
      center.seekForwardCommand, center.seekBackwardCommand,
      center.changePlaybackPositionCommand, center.changePlaybackRateCommand,
    ] {
      command.isEnabled = false
    }
  }

  func activate() {
    session.becomeActiveIfPossible { [session] active in
      AppLog.audio.notice("now playing session active=\(active) canBecomeActive=\(session.canBecomeActive)")
    }
  }

  /// Describes what is playing on the item the system publishes from.
  func update(item: AVPlayerItem?, title: String, subtitle: String?) {
    guard let item else { return }
    var metadata = [Self.metadataItem(.commonIdentifierTitle, value: title)]
    if let subtitle {
      metadata.append(Self.metadataItem(.iTunesMetadataTrackSubTitle, value: subtitle))
    }
    item.externalMetadata = metadata
  }

  func end() {
    for (command, target) in targets {
      command.removeTarget(target)
    }
    targets.removeAll()
    session.nowPlayingInfoCenter.nowPlayingInfo = nil
  }

  private func register(_ command: MPRemoteCommand, _ action: @escaping () -> Void) {
    command.isEnabled = true
    let target = command.addTarget { _ in
      DispatchQueue.main.async(execute: action)
      return .success
    }
    targets.append((command, target))
  }

  private static func metadataItem(_ identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = identifier
    item.value = value as NSString
    item.extendedLanguageTag = "und"
    return item
  }
}
