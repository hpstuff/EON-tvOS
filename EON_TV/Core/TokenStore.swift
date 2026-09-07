import Security
import Foundation

actor TokenStore {
  private let accessKey = "access_token"
  private let refreshKey = "refresh_token"
  private let clientAccessKey = "client_access_token"
  
  
  private let streamKey = "stream_key"
  private let streamUn = "stream_un"
  private let issuerKey = "token_client"

  func save(accessToken: String, refreshToken: String? = nil) async {
    await Task.detached {
      await KeychainHelper.standard.save(accessToken, forKey: self.accessKey)
      if let refreshToken {
        await KeychainHelper.standard.save(refreshToken, forKey: self.refreshKey)
      }
    }.value
  }
  
  func saveStreamKeys(streamKey: String, streamUn: String) async {
    await Task.detached {
      await KeychainHelper.standard.save(streamKey, forKey: self.streamKey)
      await KeychainHelper.standard.save(streamUn, forKey: self.streamUn)
    }.value
  }
  
  /// Remembers which client identity the current tokens were issued to.
  func saveIssuer(_ client: ClientIdentity) async {
    await Task.detached {
      await KeychainHelper.standard.save(client.rawValue, forKey: self.issuerKey)
    }.value
  }

  func getIssuer() async -> ClientIdentity? {
    await MainActor.run {
      KeychainHelper.standard.read(forKey: self.issuerKey).flatMap(ClientIdentity.init(rawValue:))
    }
  }

  func getStreamKey() async -> String? {
    await MainActor.run {
      KeychainHelper.standard.read(forKey: self.streamKey)
    }
  }
  
  func getStreamUn() async -> String? {
    await MainActor.run {
      KeychainHelper.standard.read(forKey: self.streamUn)
    }
  }

  func getAccessToken() async -> String? {
    await MainActor.run {
      KeychainHelper.standard.read(forKey: self.accessKey)
    }
  }

  func getRefreshToken() async -> String? {
    await MainActor.run {
      KeychainHelper.standard.read(forKey: self.refreshKey)
    }
  }
  
  func getClientAccessToken() async -> String? {
    await MainActor.run {
      KeychainHelper.standard.read(forKey: self.clientAccessKey)
    }
  }

  func clear() async {
    await Task.detached {
      await KeychainHelper.standard.delete(forKey: self.accessKey)
      await KeychainHelper.standard.delete(forKey: self.refreshKey)
      await KeychainHelper.standard.delete(forKey: self.clientAccessKey)
      await KeychainHelper.standard.delete(forKey: self.issuerKey)
    }.value
  }
}
