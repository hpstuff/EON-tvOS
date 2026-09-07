import Foundation

public struct ClientAccessToken: Codable {
  public let scope: String
  public let access_token: String
  public let token_type: String
  public let expires_in: Int
  public let jti: String
  
  func getAccessToken() -> String {
    return "\(token_type) \(access_token)"
  }
}
