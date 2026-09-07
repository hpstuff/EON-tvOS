import Foundation

// App-level conveniences over the SDK's `Schedule` (an EPG programme). Times in the SDK are
// epoch milliseconds; everything here keeps that unit and converts only for display.
extension Schedule {
  var startDate: Date { Date(timeIntervalSince1970: TimeInterval(startTime) / 1000) }
  var endDate: Date { Date(timeIntervalSince1970: TimeInterval(endTime) / 1000) }
  var durationMs: Int { max(0, endTime - startTime) }
  var durationMinutes: Int { durationMs / 60_000 }

  /// Uses the SDK's liveness rule so the app and SDK never disagree about "on air".
  func isAiring(at nowMs: Int) -> Bool { isScheduleLive(self, liveTime: nowMs) }
  func hasEnded(at nowMs: Int) -> Bool { endTime <= nowMs }
  func isUpcoming(at nowMs: Int) -> Bool { startTime > nowMs }

  func progress(at nowMs: Int) -> Double {
    guard durationMs > 0 else { return 0 }
    return min(1, max(0, Double(nowMs - startTime) / Double(durationMs)))
  }

  func remainingMinutes(at nowMs: Int) -> Int { max(0, (endTime - nowMs) / 60_000) }
  func minutesUntilStart(at nowMs: Int) -> Int { max(0, (startTime - nowMs) / 60_000) }

  var posterURL: URL? {
    guard image != nil, baseURL != nil else { return nil }
    return URL(string: poster)
  }

  var timeRangeText: String { "\(startDate.shortTime) – \(endDate.shortTime)" }

  var descriptionText: String? {
    shortDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  /// Secondary line for cards: "S02, E05 · Original Title" when available.
  var subtitleText: String? {
    var parts: [String] = []
    if let episode = seasonAndEpisode { parts.append(episode) }
    if let original = originalTitle?.trimmingCharacters(in: .whitespaces).nilIfEmpty, original != title {
      parts.append(original)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

extension Date {
  var shortTime: String { formatted(date: .omitted, time: .shortened) }

  /// "Today", "Yesterday", "Tomorrow", otherwise the weekday name.
  func relativeDayLabel(calendar: Calendar = .current) -> String {
    if calendar.isDateInToday(self) { return "Today" }
    if calendar.isDateInYesterday(self) { return "Yesterday" }
    if calendar.isDateInTomorrow(self) { return "Tomorrow" }
    return formatted(.dateTime.weekday(.wide))
  }

  var shortDayLabel: String { formatted(.dateTime.weekday(.abbreviated).day()) }
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Int {
  /// Epoch milliseconds → `Date`.
  var dateFromMs: Date { Date(timeIntervalSince1970: TimeInterval(self) / 1000) }
}
