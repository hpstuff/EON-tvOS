import Foundation

public struct RenderProfile: Identifiable, Codable {
  public let id: Int
  public let name: String
  public let coreStreamId: String
  public let height: Int
  public let width: Int
  public let audioBitrate: Int
  public let videoBitrate: Int
}
