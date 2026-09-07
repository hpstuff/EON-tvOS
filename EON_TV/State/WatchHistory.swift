import Foundation
import Observation

/// What the viewer has been watching: recently tuned channels and catch-up positions.
/// The platform has no history API, so this is kept on the device.
@Observable
final class WatchHistory {
  struct ResumeEntry: Codable, Hashable, Identifiable {
    let scheduleID: Int
    let channelID: Int
    let title: String
    let startTime: Int
    let endTime: Int
    let posterPath: String?
    var positionMs: Int
    var updatedAt: Date

    var id: Int { scheduleID }
    var durationMs: Int { max(1, endTime - startTime) }
    var fraction: Double { min(1, max(0, Double(positionMs) / Double(durationMs))) }
  }

  private static let channelsKey = "eon.history.recentChannels"
  private static let resumeKey = "eon.history.resume"
  private static let maxChannels = 12
  private static let maxResumes = 20

  private(set) var recentChannelIDs: [Int] {
    didSet { UserDefaults.standard.set(recentChannelIDs, forKey: Self.channelsKey) }
  }

  private(set) var resumes: [ResumeEntry] {
    didSet {
      if let data = try? JSONEncoder().encode(resumes) {
        UserDefaults.standard.set(data, forKey: Self.resumeKey)
      }
    }
  }

  init() {
    recentChannelIDs = UserDefaults.standard.array(forKey: Self.channelsKey) as? [Int] ?? []
    if let data = UserDefaults.standard.data(forKey: Self.resumeKey),
       let decoded = try? JSONDecoder().decode([ResumeEntry].self, from: data) {
      resumes = decoded
    } else {
      resumes = []
    }
  }

  var lastChannelID: Int? { recentChannelIDs.first }

  func recordChannel(_ channelID: Int) {
    var list = recentChannelIDs.filter { $0 != channelID }
    list.insert(channelID, at: 0)
    recentChannelIDs = Array(list.prefix(Self.maxChannels))
  }

  /// Records a catch-up position. Entries near the start or the end are dropped so the
  /// "Continue Watching" shelf only offers programmes worth resuming.
  func updateResume(for schedule: Schedule, positionMs: Int) {
    let duration = max(1, schedule.durationMs)
    let fraction = Double(positionMs) / Double(duration)
    var list = resumes.filter { $0.scheduleID != schedule.id }
    if fraction > 0.02 && fraction < 0.95 {
      list.insert(
        ResumeEntry(
          scheduleID: schedule.id,
          channelID: schedule.channelId,
          title: schedule.title,
          startTime: schedule.startTime,
          endTime: schedule.endTime,
          posterPath: schedule.image?.path,
          positionMs: positionMs,
          updatedAt: Date()
        ),
        at: 0
      )
    }
    resumes = Array(list.prefix(Self.maxResumes))
  }

  func resumePosition(for scheduleID: Int) -> Int? {
    resumes.first { $0.scheduleID == scheduleID }?.positionMs
  }

  func removeResume(_ scheduleID: Int) {
    resumes.removeAll { $0.scheduleID == scheduleID }
  }

  /// Drops entries that can no longer be played back.
  func prune(nowMs: Int, channels: [Int: Channel]) {
    let kept = resumes.filter { entry in
      guard let channel = channels[entry.channelID], channel.canCatchUp else { return false }
      let earliestMs = Double(nowMs) - channel.catchUpWindow * 1000
      return Double(entry.startTime) >= earliestMs
    }
    if kept.count != resumes.count { resumes = kept }
  }

  func clear() {
    recentChannelIDs = []
    resumes = []
  }
}
