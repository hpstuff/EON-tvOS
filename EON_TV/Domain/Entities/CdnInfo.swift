import Foundation

public struct CdnInfo: Identifiable, Codable {
  public let id: Int
  public let identifier: String
  public let domains: Domains
}

public struct Domains: Codable {
  public let baseApi: Domain
}

public struct Domain: Codable {
  public let af31: String
  public let be: String
}
