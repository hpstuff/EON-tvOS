import Foundation
import CryptoKit

public class StreamingRepositoryImpl: StreamingRepository {
  private let streamingService: StreamingService
  private let tokenStore: TokenStore
  private let deviceStore: DeviceStore
  
  init(streamingService: StreamingService, tokenStore: TokenStore, deviceStore: DeviceStore) {
    self.streamingService = streamingService
    self.tokenStore = tokenStore
    self.deviceStore = deviceStore
  }
  
  public func getStreamingUrl(forChannel channel: Channel, startTime: Int? = nil) async throws -> (URL, Int, Int) {
    let servers = try await streamingService.getServers()
    let profiles = try await streamingService.getRenderProfiles()
    let provider = try await streamingService.getProvider()
    let time = try await streamingService.getTime()
    
    var isLive = startTime == nil

    if let startTime = startTime {
      if areTimestampsClose(TimeInterval(startTime/1000), ServerTime.shared.currentTimeInterval(), marginSeconds: 6) {
        isLive = true
      }
    }

    var streamingProfile = "hp7000"
    var rndbitrate = 0
    var current_bitrate = 0
    var currentProfile: RenderProfile?
    
    for id in channel.publishingPoint[0].profileIds {
      if let current = profiles.first(where: { profile in profile.id == id }) {
        current_bitrate = current.videoBitrate
        
        if current_bitrate > rndbitrate {
          currentProfile = current
          rndbitrate = current_bitrate
        }
      }
    }
    
    if let _ = currentProfile?.coreStreamId {
      streamingProfile = currentProfile!.coreStreamId
    }
    
    let session_id = UUID().uuidString.lowercased()
    
    let pool = isLive ? servers.live_servers : servers.timeshift_servers
    guard let server = pool.indices.contains(3) ? pool[3] : pool.first else {
      throw StreamingError.missingData
    }
    
    guard let streamUser = await tokenStore.getStreamUn() else {
      throw StreamingError.missingData
    }
    
    guard let streamKey = await tokenStore.getStreamKey() else {
      throw StreamingError.missingData
    }

    // The platform ties stream sessions to the device number that signed in.
    guard let device = await deviceStore.registration() else {
      throw StreamingError.missingData
    }
    
    var plain_aes_props = [
      "channel=\(channel.publishingPoint[0].publishingPoint);",
      "stream=\(streamingProfile);",
      "sp=\(provider.identifier);",
      "u=\(streamUser);",
      "m=\(server.ip);",
      "device=\(device.deviceNumber);",
      "ctime=\(time.time);",
      "lang=eng;",
      "player=m3u8;",
      "aa=\(channel.aaEnabled ? "true" : "false");",
      "conn=ETHERNET;", //"WI_FI", "ETHERNET", "MOBILE", "BROWSER"
      "minvbr=100;",
      "ss=\(streamKey);",
      "session=\(session_id);",
      "maxvbr=\(rndbitrate);"
    ]
    
    if !isLive && startTime != nil {
      plain_aes_props.append("t=\(startTime!);")
    }
    
    let plain_aes = plain_aes_props.joined(separator: "")

    guard let result = decodeEonStreamKey(from: streamKey) else {
      throw StreamingError.missingData
    }
    
    guard let sig = isLive ? channel.liveConfig?.sig : channel.cutvConfig?.sig  else {
      throw StreamingError.missingData
    }
    
    let key = result.key
    let iv = result.iv.base64EncodedString()

    guard let cipher = aesEncryptCBC(iv: result.iv, key: key, plaintext: Data(plain_aes.utf8)) else {
      throw StreamingError.failToEncryptAES
    }
    
    let params = [
      "i=\(urlsafeEncode(iv))",
      "a=\(urlsafeEncode(cipher.base64EncodedString()))",
      "lang=eng",  //Android TV
      "sp=\(provider.identifier)",
      "u=\(streamUser)",
      "player=m3u8",
      "session=\(session_id)",
      "sig=\(sig)" //Android TV
    ].joined(separator: "&")
    
    let url = "https://\(server.hostname)/stream/?\(params)"

    return (URL(string: url)!, startTime ?? Int(time.time)!, Int(time.time)!)
  }
}
