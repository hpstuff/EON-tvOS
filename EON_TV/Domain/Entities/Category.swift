import Foundation

public struct Category: Identifiable, Codable {
  public let id: Int
  public let name: String
  public let defaultList: Bool
  public let channels: [ChannelOrder]
}

public struct ChannelOrder: Identifiable, Codable {
  public let id: Int
  public let position: Int
}
