import Foundation

/// Token grant response. Only `access_token` is guaranteed: a refresh may omit the refresh
/// token and the stream fields, and those must then keep their stored values.
public struct AccessToken: Codable {
  public let access_token: String
  public let refresh_token: String?
  public let token_type: String?
  public let stream_key: String?
  public let stream_un: String?
  
  func getAccessToken() -> String {
    return "\(token_type ?? "Bearer") \(access_token)"
  }
}
