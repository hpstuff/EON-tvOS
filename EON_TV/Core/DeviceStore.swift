import Foundation

/// The identity this installation presents to the platform: a serial minted once and kept for
/// the life of the installation, and the registration the platform issued for that serial.
///
/// The serial must never change: registering with a new one creates another device on the
/// household, and providers cap the number of devices, so it lives in the keychain rather
/// than in a cache directory or `identifierForVendor`.
actor DeviceStore {
  private let serialKey = "device_serial"
  private let deviceIdKey = "device_id"
  private let deviceNumberKey = "device_number"
  private let friendlyIdKey = "device_friendly_id"

  /// The stored serial, minting and persisting one on first use.
  func serial() -> String {
    if let existing = KeychainHelper.standard.read(forKey: serialKey), !existing.isEmpty {
      return existing
    }
    let fresh = UUID().uuidString
    KeychainHelper.standard.save(fresh, forKey: serialKey)
    return fresh
  }

  /// The registration the platform issued for this serial, if one is stored.
  func registration() -> Device? {
    guard let idText = KeychainHelper.standard.read(forKey: deviceIdKey),
          let id = Int(idText),
          let number = KeychainHelper.standard.read(forKey: deviceNumberKey),
          !number.isEmpty
    else { return nil }
    return Device(
      deviceId: id,
      deviceNumber: number,
      friendlyId: KeychainHelper.standard.read(forKey: friendlyIdKey) ?? ""
    )
  }

  func save(_ device: Device) {
    KeychainHelper.standard.save(String(device.deviceId), forKey: deviceIdKey)
    KeychainHelper.standard.save(device.deviceNumber, forKey: deviceNumberKey)
    KeychainHelper.standard.save(device.friendlyId, forKey: friendlyIdKey)
  }

  /// Forgets the registration but keeps the serial, so the next registration resolves to the
  /// same device unless the provider removed it.
  func clearRegistration() {
    KeychainHelper.standard.delete(forKey: deviceIdKey)
    KeychainHelper.standard.delete(forKey: deviceNumberKey)
    KeychainHelper.standard.delete(forKey: friendlyIdKey)
  }
}
