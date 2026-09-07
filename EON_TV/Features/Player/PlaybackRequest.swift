import Foundation
import Observation

/// What the viewer asked to watch. Carries the surrounding line-up so the player can flip
/// channels with the remote without asking the store where it came from.
struct PlaybackRequest: Identifiable, Hashable {
  enum Mode: Hashable {
    /// The live edge of the channel.
    case live
    /// The programme currently airing, from its beginning (timeshift stream).
    case startOver(Schedule)
    /// A past programme from `offsetMs` into it (timeshift stream).
    case catchUp(Schedule, offsetMs: Int)
    /// The timeshift stream from an absolute wall-clock instant (seeking, pause-resume).
    case timeshift(atMs: Int)

    var schedule: Schedule? {
      switch self {
      case .live, .timeshift: return nil
      case .startOver(let schedule), .catchUp(let schedule, _): return schedule
      }
    }

    /// The wall-clock instant the stream should start from; `nil` means the live edge.
    var requestedStartMs: Int? {
      switch self {
      case .live: return nil
      case .startOver(let schedule): return schedule.startTime
      case .catchUp(let schedule, let offsetMs): return schedule.startTime + max(0, offsetMs)
      case .timeshift(let atMs): return atMs
      }
    }
  }

  let id = UUID()
  let channel: Channel
  let mode: Mode
  let lineup: [Channel]
}

/// App-wide entry point for playback and cross-screen navigation. Screens ask; the tab shell
/// presents. Keeping this out of the stores means content state never knows about screens.
@Observable
final class PlaybackCoordinator {
  enum Section: Hashable {
    case home, guide, channels, search, settings
  }

  var request: PlaybackRequest?
  var detail: ContentStore.ProgramItem?
  var selectedSection: Section = .home
  /// Channel the guide should reveal next time it appears (set by "Open in Guide").
  var guideTarget: Channel?

  func playLive(_ channel: Channel, lineup: [Channel]) {
    request = PlaybackRequest(channel: channel, mode: .live, lineup: lineup)
  }

  func startOver(_ schedule: Schedule, on channel: Channel, lineup: [Channel]) {
    request = PlaybackRequest(channel: channel, mode: .startOver(schedule), lineup: lineup)
  }

  func catchUp(_ schedule: Schedule, on channel: Channel, offsetMs: Int = 0, lineup: [Channel]) {
    request = PlaybackRequest(channel: channel, mode: .catchUp(schedule, offsetMs: offsetMs), lineup: lineup)
  }

  /// The natural action for a programme card: live when airing, from the start when it has
  /// ended and catch-up is available, otherwise its details.
  func open(_ item: ContentStore.ProgramItem, nowMs: Int, lineup: [Channel], resumeMs: Int? = nil) {
    let schedule = item.schedule
    if schedule.isAiring(at: nowMs) {
      playLive(item.channel, lineup: lineup)
    } else if schedule.hasEnded(at: nowMs), item.channel.isWithinCatchUpWindow(schedule, nowMs: nowMs) {
      catchUp(schedule, on: item.channel, offsetMs: resumeMs ?? 0, lineup: lineup)
    } else {
      detail = item
    }
  }

  func showDetails(_ item: ContentStore.ProgramItem) {
    detail = item
  }

  func openGuide(for channel: Channel?) {
    guideTarget = channel
    selectedSection = .guide
  }

  func dismissPlayer() {
    request = nil
  }
}
