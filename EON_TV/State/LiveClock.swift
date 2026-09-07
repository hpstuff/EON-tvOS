import Foundation
import Observation

/// The app's single notion of "now", derived from the server-synchronised clock.
///
/// Ticks on a coarse, aligned cadence so live badges, progress bars and "on now" shelves
/// update together, in place, without rebuilding screens or disturbing focus.
@Observable
final class LiveClock {
  private(set) var nowMs: Int = ServerTime.shared.currentTimeMillis()
  private(set) var dayStart: Date = ServerTime.shared.currentDate().startOfTheDay

  /// Fired once when the local calendar day rolls over.
  var onDayChange: ((Date) -> Void)?

  private var ticker: Task<Void, Never>?
  private let interval: TimeInterval

  init(interval: TimeInterval = 15) {
    self.interval = interval
  }

  var now: Date { nowMs.dateFromMs }

  func start() {
    guard ticker == nil else { return }
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        let seconds = ServerTime.shared.currentTimeInterval()
        let wait = self.interval - seconds.truncatingRemainder(dividingBy: self.interval)
        try? await Task.sleep(for: .seconds(max(0.5, wait)))
        if Task.isCancelled { return }
        self.tick()
      }
    }
  }

  func stop() {
    ticker?.cancel()
    ticker = nil
  }

  /// Re-reads the server clock immediately (after a time sync or on foreground).
  func tick() {
    nowMs = ServerTime.shared.currentTimeMillis()
    let start = now.startOfTheDay
    if start != dayStart {
      dayStart = start
      onDayChange?(start)
    }
  }
}
