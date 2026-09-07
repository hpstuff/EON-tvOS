import Foundation

public protocol EpgRepository {
  func getSchedule(forChannel: Channel) async throws -> [Schedule]
  func getSchedule(forChannel: Channel, forDay day: Date) async throws -> [Schedule]
  func getSchedule(forChannels: [Channel]) async throws -> [Int: [Schedule]]
  func getSchedule(forChannels: [Channel], forDay day: Date) async throws -> [Int: [Schedule]]
}
