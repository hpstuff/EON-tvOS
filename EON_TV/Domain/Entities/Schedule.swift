import Foundation

public struct Schedule: Identifiable, Codable {
  public let id: Int
  public let title: String
  public let originalTitle: String?
  public let shortDescription: String?
  public let channelId: Int
  public let startTime: Int
  public let endTime: Int
  public let seasonNumber: Int?
  public let episodeNumber: Int?
  public var live: Bool
  
  public var seasonAndEpisode: String? {
    get {
      if let season = seasonNumber,
         let episode = episodeNumber {
        return "S\(String(format: "%02d", season)), E\(String(format: "%02d", episode))"
      }
      return nil
    }
  }
  
  public let images: [ChannelImage]
  
  public var baseURL: String? = nil
  
  public var image: ChannelImage? {
    get {
      return images.filter { image in
      image.size == "XL"
    }.first }
  }
  
  public var poster: String {
    get { "https://images-\(Constants.platform == "android" ? "android-tv" : "web").\(baseURL!)\(image?.path ?? "")" }
  }
  
}


extension Schedule: Equatable, Hashable {
  public static func == (lhs: Schedule, rhs: Schedule) -> Bool {
    return lhs.id == rhs.id && lhs.startTime == rhs.startTime && lhs.endTime == rhs.endTime
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(startTime)
    hasher.combine(endTime)
  }
}

extension Schedule {
  public var size: CGFloat {
    get {
      hourSize(startTime: startTime, endTime: endTime)
    }
  }
}
