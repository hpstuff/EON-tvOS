import Foundation

public class EpgRepositoryImpl: EpgRepository {
  private let streamingService: StreamingService
  private let epgService: EpgService
  
  init(epgService: EpgService, streamingService: StreamingService) {
    self.epgService = epgService
    self.streamingService = streamingService
  }
  
  public func getSchedule(forChannel channel: Channel) async throws -> [Schedule] {
    let _ = try await streamingService.getTime()
    
    return try await epgService.getEpg(
      forChannel: channel,
      startTime: nil,
      endTime: nil
    )
  }
  
  public func getSchedule(forChannel channel: Channel, forDay day: Date) async throws -> [Schedule] {
    let _ = try await streamingService.getTime()
    
    return try await epgService.getEpg(
      forChannel: channel,
      startTime: day.startOfTheDay.timestampSince1970,
      endTime: day.endOfTheDay.timestampSince1970
    )
  }
  
  public func getSchedule(forChannels channels: [Channel]) async throws -> [Int: [Schedule]] {
    return try await epgService.getEpg(forChannels: channels, startTime: nil, endTime: nil)
  }
  
  public func getSchedule(forChannels channels: [Channel], forDay day: Date) async throws -> [Int: [Schedule]] {
    return try await epgService.getEpg(
      forChannels: channels,
      startTime: day.startOfTheDay.timestampSince1970,
      endTime: day.endOfTheDay.timestampSince1970
    )
  }
  
}
