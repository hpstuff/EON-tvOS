import Foundation
import EONKit

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

  /// Time range with the day in front when the programme isn't on today — "Yesterday · 20:00 – 21:30".
  /// Continue Watching and catch-up reach back days or weeks, where an hour on its own says nothing
  /// about which showing it was.
  var dayAndTimeRangeText: String {
    guard let day = startDate.dayLabelUnlessToday() else { return timeRangeText }
    return "\(day) · \(timeRangeText)"
  }

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

  /// The day this falls on, or `nil` for today where the time alone is unambiguous. Weekday names
  /// only inside the surrounding week; beyond that a date, since catch-up windows run up to a
  /// month and "Tuesday" would then name two different days.
  func dayLabelUnlessToday(calendar: Calendar = .current, now: Date = Date()) -> String? {
    if calendar.isDateInToday(self) { return nil }
    if calendar.isDateInYesterday(self) { return "Yesterday" }
    if calendar.isDateInTomorrow(self) { return "Tomorrow" }
    let days = calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: self)
    ).day ?? 0
    if abs(days) < 7 { return formatted(.dateTime.weekday(.wide)) }
    return formatted(.dateTime.day().month(.abbreviated))
  }
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Int {
  /// Epoch milliseconds → `Date`.
  var dateFromMs: Date { Date(timeIntervalSince1970: TimeInterval(self) / 1000) }
}
