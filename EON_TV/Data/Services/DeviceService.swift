import Foundation
import UIKit

/// What the platform is told about this installation when it registers. The backend keys its
/// behaviour on `deviceType` and `platform`; the names are free text shown in the portal.
public struct DeviceProfile: Encodable {
  public let deviceName: String
  public let deviceType: String
  public let modelName: String
  public let platform: String
  public let clientSwVersion: String
  public let clientSwBuild: String?
  public let systemSwVersion: SystemVersion

  public struct SystemVersion: Encodable {
    public let name: String
    public let version: String
  }

  /// The profile that matches `Constants.platform`, with Apple TV names so the device is
  /// recognisable in the provider's device list.
  public static var appleTV: DeviceProfile {
    let bundle = Bundle.main
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    let system = UIDevice.current.systemVersion
    if Constants.platform == "android" {
      return DeviceProfile(
        deviceName: "Apple TV",
        deviceType: "Android 11",
        modelName: "Apple TV 4K",
        platform: "android_tv",
        clientSwVersion: version,
        clientSwBuild: build,
        systemSwVersion: SystemVersion(name: "tvOS", version: system)
      )
    }
    return DeviceProfile(
      deviceName: "Apple TV",
      deviceType: "web_linux_chrome",
      modelName: "Apple TV 4K",
      platform: "web",
      clientSwVersion: version,
      clientSwBuild: nil,
      systemSwVersion: SystemVersion(name: "tvOS", version: system)
    )
  }
}

/// Device registration and one-time codes on the regional API. Both endpoints are reached
/// before the viewer has a session, so they authenticate with the device client's generic
/// token from `ConfigService.getClientToken()`; Basic client credentials are refused.
public struct DeviceService {
  private let client: NetworkClient
  
  private let apiPrefix = "api-\(Constants.platform == "android" ? "android-tv" : "web")"
  
  private let baseURL: String
  
  init(client: NetworkClient, baseURL: String) {
    self.client = client
    self.baseURL = baseURL
  }

  /// Registers `serial` and returns its device. Posting a serial the platform already knows
  /// returns the existing device rather than creating another one.
  public func register(profile: DeviceProfile, serial: String, clientToken: String) async throws -> Device {
    let urlString = "https://\(apiPrefix).\(baseURL)/v1/devices"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }

    var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any] ?? [:]
    payload["serial"] = serial
    let body = try JSONSerialization.data(withJSONObject: payload)

    let (data, response) = try await client.post(url, data: body, headers: [
      "Authorization": "Bearer \(clientToken)",
      "Content-Type": "application/json",
    ])
    return try AuthError.decode(Device.self, from: data, response)
  }

  /// A code for the viewer to enter in the provider's portal. Asking again while a code is
  /// still valid returns the same code with its remaining lifetime.
  public func requestOneTimeCode(deviceNumber: String, clientToken: String) async throws -> OneTimeCode {
    var components = URLComponents(string: "https://\(apiPrefix).\(baseURL)/v1/otp")
    components?.queryItems = [URLQueryItem(name: "deviceNumber", value: deviceNumber)]
    guard let url = components?.url else {
      throw NetworkError.invalidURL
    }

    let (data, response) = try await client.get(url, headers: [
      "Authorization": "Bearer \(clientToken)"
    ])
    return try AuthError.decode(OneTimeCode.self, from: data, response)
  }
}
