import Foundation

public struct LoginService {
  private let client: NetworkClient
  
  private let apiPrefix = "api-\(Constants.platform == "android" ? "android-tv" : "web")"
  
  private let baseURL: String
  
  init(client: NetworkClient, baseURL: String) {
    self.client = client
    self.baseURL = baseURL
  }
  
  /// Password grant, issued to `Constants.passwordClient`. The username travels as an uppercase
  /// SHA-256 hex digest; the password as typed. `device` is the device number issued by
  /// `DeviceService.register`.
  public func login(username: String, password: String, device: String) async throws -> AccessToken {
    let urlString = "https://\(apiPrefix).\(baseURL)/oauth/token?grant_type=password"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    guard let hashedUsername = username.sha256()?.uppercased() else {
      throw NetworkError.missingParams
    }
      
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "username", value: hashedUsername),
      URLQueryItem(name: "password", value: password),
      URLQueryItem(name: "device_number", value: device)
    ]

    let body = components.percentEncodedQuery?.data(using: .utf8)
    
    let (data, response) = try await client.post(url, data: body, headers: [
      "Authorization": "Basic \(Constants.passwordClient.basicAuth)",
      "Content-Type": "application/x-www-form-urlencoded",
    ])
    
    return try AuthError.decode(AccessToken.self, from: data, response, grant: .password)
  }

  /// One-time-code grant, issued to `Constants.deviceClient`. Fails with
  /// `AuthError.codeNotConfirmed` until the viewer has entered the code in the provider's
  /// portal, so callers poll it while the code is valid.
  public func login(oneTimeCode: String, device: String) async throws -> AccessToken {
    var components = URLComponents(string: "https://\(apiPrefix).\(baseURL)/oauth/token")
    components?.queryItems = [
      URLQueryItem(name: "grant_type", value: "otp"),
      URLQueryItem(name: "otp", value: oneTimeCode),
      URLQueryItem(name: "device_number", value: device)
    ]
    guard let url = components?.url else {
      throw NetworkError.invalidURL
    }

    let (data, response) = try await client.post(url, data: Data("{}".utf8), headers: [
      "Authorization": "Basic \(Constants.deviceClient.basicAuth)",
      "Content-Type": "application/json",
    ])

    return try AuthError.decode(AccessToken.self, from: data, response, grant: .oneTimeCode)
  }
  
  public func getHousehold() async throws -> Household {
    let urlString = "https://\(apiPrefix).\(baseURL)/v1/households"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url)
    
    do {
      let response = try JSONDecoder().decode(Household.self, from: data)
      
      return response
    } catch {
      throw NetworkError.decodingError
    }
  }
  
  /// Refresh grant. `client` must be the identity the tokens were issued to.
  public func refreshToken(refreshToken: String, client: ClientIdentity) async throws -> AccessToken? {
    let urlString = "https://\(apiPrefix).\(baseURL)/oauth/token?grant_type=refresh_token&refresh_token=\(refreshToken)"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, response) = try await self.client.post(url, headers: [
      "Authorization": "Basic \(client.basicAuth)"
    ])
    
    return try AuthError.decode(AccessToken.self, from: data, response, grant: .refresh)
  }
  
}
