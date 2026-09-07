import Foundation

// App-level conveniences over the SDK's `Channel`. These never change the SDK's
// behaviour; they only add crash-safe accessors and capability checks the UI needs.
extension Channel {
  /// Artwork host, mirroring the SDK's URL scheme for channel and programme images.
  static func imageHost(baseURL: String) -> String {
    "https://images-\(Constants.platform == "android" ? "android-tv" : "web").\(baseURL)"
  }

  /// A logo URL that can never crash. Uses the SDK's XL rendition when present and
  /// falls back to the largest available image otherwise.
  var logoURL: URL? {
    guard let baseURL else { return nil }
    if images.contains(where: { $0.size == "XL" }) { return URL(string: logo) }
    guard let largest = images.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
    return URL(string: Channel.imageHost(baseURL: baseURL) + largest.path)
  }

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

extension Channel: Equatable, Hashable {
  public static func == (lhs: Channel, rhs: Channel) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ChannelCategory: Equatable, Hashable {
  public static func == (lhs: ChannelCategory, rhs: ChannelCategory) -> Bool {
    lhs.id == rhs.id && lhs.channels.map(\.id) == rhs.channels.map(\.id)
  }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
