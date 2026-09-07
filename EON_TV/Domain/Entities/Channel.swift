import Foundation

public struct Channel: Identifiable, Codable {
  public let id: Int
  public let name: String
  public let shortName: String
  
  public let images: [ChannelImage]
  
  public var baseURL: String? = nil
  
  public var image: ChannelImage {
    get {
      return images.filter { image in
      image.size == "XL"
    }.first! }
  }
  
  public var logo: String {
    get { "https://images-\(Constants.platform == "android" ? "android-tv" : "web").\(baseURL!)\(image.path)" }
  }
  
  public let publishingPoint: [PublishingPoint]
  
  public let subscribed: Bool
  
  public let drmRequired: Bool
  public let castEnabled: Bool
  public let liveEnabled: Bool
  public let cutvEnabled: Bool
  public let drEnabled: Bool
  public let aaEnabled: Bool
  
  public let startOverEnabled: Bool
  
  public let cutvDelay: Int
  public var liveConfig: PlayerConfig? {
    get { publishingPoint[0].playerCfgs.first { config in config.type == "live" } }
  }
  public var cutvConfig: PlayerConfig? {
    get { publishingPoint[0].playerCfgs.first { config in config.type == "cutv" } }
  }
}

public struct ChannelImage: Codable {
  public let path: String
  public let width: Int
  public let height: Int
  public let size: String
  public let type: String
}

public struct PublishingPoint: Codable {
  public let publishingPoint: String
  public let audioLanguage: String
  public let subtitleLanguage: String
  public let profileIds: [Int]
  public let playerCfgs: [PlayerConfig]
}

public struct PlayerConfig: Identifiable, Codable {
  public let id: Int;
  public let type: String;
  public let sig: String;
}
