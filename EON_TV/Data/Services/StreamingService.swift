import Foundation

public struct StreamingService {
  private let client: NetworkClient
  
  private let apiPrefix = "api-\(Constants.platform == "android" ? "android-tv" : "web")"
  
  private let baseURL: String
  
  init(client: NetworkClient, baseURL: String) {
    self.client = client
    self.baseURL = baseURL
  }
  
  public func getServers() async throws -> Servers {
    let urlString = "https://\(apiPrefix).\(baseURL)/v1/servers"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url)
    
    do {
      let response = try JSONDecoder().decode(Servers.self, from: data)
      
      return response
    } catch {
      throw NetworkError.decodingError
    }
  }
  
  public func getRenderProfiles() async throws -> [RenderProfile] {
    let urlString = "https://\(apiPrefix).\(baseURL)/v1/rndprofiles"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url)
    
    do {
      let response = try JSONDecoder().decode([RenderProfile].self, from: data)
      
      return response
    } catch {
      throw NetworkError.decodingError
    }
  }
  
  public func getProvider() async throws -> Provider {
    let urlString = "https://\(apiPrefix).\(baseURL)/v1/sp"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url)
    
    do {
      let response = try JSONDecoder().decode(Provider.self, from: data)
      
      return response
    } catch {
      throw NetworkError.decodingError
    }
  }
  
  public func getTime() async throws -> Time {
    let urlString = "https://\(apiPrefix).\(baseURL)/v1/time"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url)
    
    do {
      let response = try JSONDecoder().decode(Time.self, from: data)

      ServerTime.shared.sync(with: response.time)
      
      return response
    } catch {
      throw NetworkError.decodingError
    }
  }
  
}
