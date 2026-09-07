import Foundation

/// Broker discovery: the client (generic) token and the CDN list that names the regional API
/// hosts. Device registration lives in `DeviceService` on the regional host.
public struct ConfigService {
  private let client: NetworkClient
  
  private let baseURL = "global.united.cloud"
  
  init(client: NetworkClient) {
    self.client = client
  }
  
  /// Client (generic) token of the device identity, for broker, registration and code requests.
  public func getClientToken() async throws -> ClientAccessToken {
    let urlString = "https://broker.\(baseURL)/oauth/token?grant_type=client_credentials"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.post(url, headers: [
      "Authorization": "Basic \(Constants.deviceClient.basicAuth)"
    ])
    
    do {
      let response = try JSONDecoder().decode(ClientAccessToken.self, from: data)
      return response
    } catch {
      throw NetworkError.decodingError
    }
  }
  
  public func cdnInfo(accessToken: String) async throws -> [CdnInfo] {
    let urlString = "https://broker.\(baseURL)/v1/cdninfo"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url, headers: [
      "Authorization": "Bearer \(accessToken)"
    ])
    
    do {
      let response = try JSONDecoder().decode([CdnInfo].self, from: data)
      return response
    } catch {
      throw NetworkError.decodingError
    }
  }
}
