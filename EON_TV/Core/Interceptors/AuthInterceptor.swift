import Foundation

final class AuthInterceptor: Interceptor {
  private let tokenStore: TokenStore
  private let loginService: LoginService

  init(tokenStore: TokenStore, loginService: LoginService) {
    self.tokenStore = tokenStore
    self.loginService = loginService
  }

  func interceptRequest(_ request: URLRequest) async throws -> URLRequest {
    var modified = request
    if let token = await tokenStore.getAccessToken() {
      if let _ = request.value(forHTTPHeaderField: "Authorization") {} else {
        modified.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }
    }
    return modified
  }

  func interceptResponse(_ data: Data, _ response: URLResponse, for request: URLRequest) async throws -> (Data, URLResponse) {
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 else {
      return (data, response)
    }
    
    guard let refreshToken = await tokenStore.getRefreshToken() else {
      return (data, response)
    }

    do {
      // Refresh through the client the tokens were issued to; older sessions predate the
      // record and came from the device client.
      let issuer = await tokenStore.getIssuer() ?? Constants.deviceClient
      let newTokens = try await loginService.refreshToken(refreshToken: refreshToken, client: issuer)
      
      guard let tokens = newTokens else {
        return (data, response)
      }
      // A refresh may omit the refresh token and stream fields; keep the stored ones then.
      await tokenStore.save(accessToken: tokens.access_token, refreshToken: tokens.refresh_token)
      if let streamKey = tokens.stream_key, let streamUn = tokens.stream_un {
        await tokenStore.saveStreamKeys(streamKey: streamKey, streamUn: streamUn)
      }
      
      var retry = request
      retry.setValue("Bearer \(tokens.access_token)", forHTTPHeaderField: "Authorization")
      return try await URLSession.shared.data(for: retry)
    } catch {
      return (data, response)
    }
  }
}
