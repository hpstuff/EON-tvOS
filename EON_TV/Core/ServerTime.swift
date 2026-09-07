import Foundation

class ServerTime {
  static let shared = ServerTime()
  private init() {}
  
  private var offset: TimeInterval = 0

  /// Syncs local time with server-provided timestamp (string or number, in milliseconds)
  func sync(with serverTimestamp: Any) {
    guard let millis = parseTimestamp(serverTimestamp) else {
      print("⚠️ Invalid server timestamp: \(serverTimestamp)")
      return
    }

    let serverSeconds = millis / 1000
    let deviceSeconds = Date().timeIntervalSince1970
    offset = serverSeconds - deviceSeconds
  }

  /// Returns a Date object adjusted to server time
  func currentDate() -> Date {
    return Date().addingTimeInterval(offset)
  }

  /// Returns a timestamp (in seconds) adjusted to server time
  func currentTimeInterval() -> TimeInterval {
    return Date().timeIntervalSince1970 + offset
  }

  /// Returns a timestamp (in milliseconds) adjusted to server time
  func currentTimeMillis() -> Int {
    return Int((Date().timeIntervalSince1970 + offset) * 1000)
  }

  private func parseTimestamp(_ value: Any) -> TimeInterval? {
    if let str = value as? String, let millis = Double(str) {
      return millis
    } else if let millis = value as? Double {
      return millis
    } else if let millis = value as? Int64 {
      return TimeInterval(millis)
    } else if let millis = value as? Int {
      return TimeInterval(millis)
    }
    return nil
  }
}
