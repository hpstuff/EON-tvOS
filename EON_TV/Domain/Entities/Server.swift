import Foundation

public struct Servers: Codable {
  public let live_servers: [Server]
  public let live_servers_id: String
  public let live_servers_retry: Int
  
  public let timeshift_servers: [Server]
  public let timeshift_servers_id: String
  public let timeshift_servers_retry: Int
  
  public let vod_servers: [Server]
  public let vod_servers_id: String
  public let vod_servers_retry: Int
  
  public let push_servers: [Server]
  public let push_servers_id: String
  public let push_servers_retry: Int
}

public struct Server: Identifiable, Codable {
  public let id: String
  public let ip: String
  public let hostname: String
}
