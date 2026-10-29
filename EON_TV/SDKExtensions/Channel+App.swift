import Foundation
import EONKit

// App-level conveniences over the SDK's `Channel`. These never change the SDK's
// behaviour; they only add crash-safe accessors and capability checks the UI needs.
extension Channel {
  /// The 16:9 logo, sharp at the sizes the app draws it (up to the player's 90pt).
  var logoURL: URL? { logoURL(.wide16x9, minHeight: 144) }

  /// The 3:1 logo, which fills a wide row such as the guide's channel column better; falls
  /// back to the 16:9 logo for channels that have none.
  var wideLogoURL: URL? { logoURL(.wide3x1, minHeight: 90) ?? logoURL }

  var primaryPublishingPoint: PublishingPoint? { publishingPoint.first }

  var livePlayerConfig: PlayerConfig? {
    primaryPublishingPoint?.playerCfgs.first { $0.type == "live" }
  }

  var catchUpPlayerConfig: PlayerConfig? {
    primaryPublishingPoint?.playerCfgs.first { $0.type == "cutv" }
  }

  var canPlayLive: Bool { liveEnabled && livePlayerConfig != nil }
  var canCatchUp: Bool { cutvEnabled && catchUpPlayerConfig != nil }
  /// Start-over is served by the timeshift (catch-up) stream, so it needs both flags.
  var canStartOver: Bool { startOverEnabled && canCatchUp }

  /// How far back catch-up reaches. `cutvDelay` arrives without a documented unit, so it is
  /// normalised heuristically (days, hours, minutes, seconds, milliseconds) and defaults to
  /// seven days when absent. Playback requests outside the true window fail gracefully.
  var catchUpWindow: TimeInterval {
    guard canCatchUp else { return 0 }
    let value = Double(cutvDelay)
    switch value {
    case ...0: return 7 * 86_400
    case ...31: return value * 86_400
    case ...1_000: return value * 3_600
    case ...100_000: return value * 60
    case ...100_000_000: return value
    default: return value / 1_000
    }
  }

  /// Whether a programme on this channel can be played from its beginning right now.
  func isWithinCatchUpWindow(_ schedule: Schedule, nowMs: Int) -> Bool {
    guard canCatchUp, schedule.channelId == id, schedule.startTime < nowMs else { return false }
    let earliestMs = Double(nowMs) - catchUpWindow * 1000
    return Double(schedule.startTime) >= earliestMs
  }
}
