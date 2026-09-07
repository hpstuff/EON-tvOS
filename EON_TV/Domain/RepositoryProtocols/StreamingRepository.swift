import Foundation
public protocol StreamingRepository {
  func getStreamingUrl(forChannel: Channel, startTime: Int?) async throws -> (URL, Int, Int)
}
