public protocol AuthRepository {
  /// Signs in with a password, registering this device with the platform first when needed.
  func login(username: String, password: String) async throws -> Household
  /// Issues a code for this device that the viewer confirms in the provider's portal.
  func requestOneTimeCode() async throws -> OneTimeCode
  /// Exchanges a code the viewer may have confirmed. Throws `AuthError.codeNotConfirmed`
  /// until they have, so it can be polled while the code is valid.
  func login(oneTimeCode: OneTimeCode) async throws -> Household
  func getHousehold() async throws -> Household
  /// The device registration this installation holds, if any.
  func registeredDevice() async -> Device?
}
