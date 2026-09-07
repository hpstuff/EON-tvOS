import Foundation

/// Errors the platform's OAuth and device endpoints report, mapped from their JSON bodies.
public enum AuthError: Error, Equatable {
  /// The platform has no record of the device number presented: it was never registered, or
  /// the viewer removed it in the provider's portal.
  case deviceNotRegistered
  /// Wrong username or password.
  case badCredentials
  /// The one-time code has not been confirmed in the provider's portal yet, or is wrong or expired.
  case codeNotConfirmed
  /// The refresh token can no longer be used.
  case sessionExpired
  /// The client identity is not allowed to use this grant.
  case grantNotAllowed
  /// Any other error the platform described.
  case platform(code: String, description: String)
  /// A non-2xx status without a readable error body.
  case httpStatus(Int)
}

/// The two body shapes the platform uses: OAuth (`error`/`error_description`) and the
/// resource servers' `status`/`error`/`errorMessage`.
nonisolated struct PlatformErrorBody: Decodable {
  let error: String?
  let error_description: String?
  let errorMessage: String?
  let status: Int?
}

extension AuthError {
  enum Grant { case password, oneTimeCode, refresh, none }

  /// Decodes a successful payload, or throws the `AuthError` the response describes.
  static func decode<T: Decodable>(_ type: T.Type, from data: Data, _ response: URLResponse, grant: Grant = .none) throws -> T {
    let status = (response as? HTTPURLResponse)?.statusCode ?? 200
    guard (200..<300).contains(status) else {
      throw AuthError.from(data: data, status: status, grant: grant)
    }
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw NetworkError.decodingError
    }
  }

  static func from(data: Data, status: Int, grant: Grant) -> AuthError {
    guard let body = try? JSONDecoder().decode(PlatformErrorBody.self, from: data) else {
      return .httpStatus(status)
    }
    let description = body.error_description ?? body.errorMessage ?? ""
    switch (body.error ?? "", grant) {
    case ("invalid_device", _):
      return .deviceNotRegistered
    case ("invalid_grant", .password):
      return .badCredentials
    case ("unauthorized", .oneTimeCode):
      return .codeNotConfirmed
    case ("invalid_token", _), ("invalid_grant", .refresh):
      return .sessionExpired
    case ("invalid_client", _):
      return .grantNotAllowed
    case (let code, _):
      return .platform(code: code, description: description)
    }
  }
}
