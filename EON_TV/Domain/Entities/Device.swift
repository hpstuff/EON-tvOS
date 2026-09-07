import Foundation

/// A device registration issued by the platform. `deviceNumber` is required by every token
/// grant and by stream requests; `friendlyId` is the short name shown in the provider's portal.
public struct Device: Codable, Equatable {
  public let deviceId: Int
  public let deviceNumber: String
  public let friendlyId: String

  public init(deviceId: Int, deviceNumber: String, friendlyId: String) {
    self.deviceId = deviceId
    self.deviceNumber = deviceNumber
    self.friendlyId = friendlyId
  }
}

/// A one-time code the viewer confirms in the provider's portal to sign this device in.
public struct OneTimeCode: Codable, Equatable {
  public let otp: String
  public let expiresInSeconds: Int

  public init(otp: String, expiresInSeconds: Int) {
    self.otp = otp
    self.expiresInSeconds = expiresInSeconds
  }
}
