import Foundation

public struct ChannelsService {
  private let client: NetworkClient
  
  private let apiPrefix = "api-\(Constants.platform == "android" ? "android-tv" : "web")"
  
  private let baseURL: String
  
  init(client: NetworkClient, baseURL: String) {
    self.client = client
    self.baseURL = baseURL
  }
  
  public func getChannels() async throws -> [Channel] {
    let urlString = "https://\(apiPrefix).\(baseURL)/v3/channels?channelType=TV"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url)
    
    do {
      let response = try JSONDecoder().decode([Channel].self, from: data)
      
      return response.map { channel in
        var clone = channel
        clone.baseURL = baseURL
        return clone
      }
    } catch {
      throw NetworkError.decodingError
    }
  }
  
  public func getCategries() async throws -> [Category] {
    let urlString = "https://\(apiPrefix).\(baseURL)/v2/categories/TV"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url)
    
    do {
      let response = try JSONDecoder().decode([Category].self, from: data)
      
      return response
    } catch {
      throw NetworkError.decodingError
    }
  }
}
