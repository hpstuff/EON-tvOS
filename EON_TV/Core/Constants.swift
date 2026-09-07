//
//  Constants.swift
//  EON TV
//
//  Created by Rumen Russanov on 10.10.25.
//

/// The official EON client identities the app can present. The platform keys its behaviour on
/// them: the Android TV client is listed as a TV box in the provider's portal but is refused
/// the password grant ("Unauthorized grant type"), while the Web client may sign in with a
/// password. The raw value is persisted next to tokens so a refresh uses the issuing client.
public enum ClientIdentity: String {
  case androidTV = "android_tv"
  case web

  public var id: String {
    switch self {
    case .androidTV: return Secrets.androidTVClientID
    case .web: return Secrets.webClientID
    }
  }

  public var secret: String {
    switch self {
    case .androidTV: return Secrets.androidTVClientSecret
    case .web: return Secrets.webClientSecret
    }
  }

  /// Value for an `Authorization: Basic` header.
  public var basicAuth: String { "\(id):\(secret)".toBase64() }
}

struct Constants {
  /// Identity this Apple TV registers under and uses for one-time codes and the code grant,
  /// so the portal lists it as a TV box.
  static let deviceClient: ClientIdentity = .androidTV
  /// Identity for the password grant, the only client allowed to use it.
  static let passwordClient: ClientIdentity = .web
  
  static public let platform = "android" // android, web
}
