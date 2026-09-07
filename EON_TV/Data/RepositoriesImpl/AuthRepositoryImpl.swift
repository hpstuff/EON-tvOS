import Foundation

public class AuthRepositoryImpl: AuthRepository {
  private let loginService: LoginService
  private let deviceService: DeviceService
  private let configService: ConfigService
  private let tokenStore: TokenStore
  private let deviceStore: DeviceStore
  private let profile: DeviceProfile
  
  init(
    loginService: LoginService,
    deviceService: DeviceService,
    configService: ConfigService,
    tokenStore: TokenStore,
    deviceStore: DeviceStore,
    profile: DeviceProfile
  ) {
    self.loginService = loginService
    self.deviceService = deviceService
    self.configService = configService
    self.tokenStore = tokenStore
    self.deviceStore = deviceStore
    self.profile = profile
  }
  
  public func login(username: String, password: String) async throws -> Household {
    let tokens = try await withRegisteredDevice { device in
      try await loginService.login(username: username, password: password, device: device.deviceNumber)
    }
    await store(tokens, issuedTo: Constants.passwordClient)
    return try await getHousehold()
  }

  public func requestOneTimeCode() async throws -> OneTimeCode {
    try await withRegisteredDevice { device in
      let clientToken = try await configService.getClientToken()
      return try await deviceService.requestOneTimeCode(deviceNumber: device.deviceNumber, clientToken: clientToken.access_token)
    }
  }

  public func login(oneTimeCode: OneTimeCode) async throws -> Household {
    guard let device = await deviceStore.registration() else {
      throw AuthError.deviceNotRegistered
    }
    let tokens = try await loginService.login(oneTimeCode: oneTimeCode.otp, device: device.deviceNumber)
    await store(tokens, issuedTo: Constants.deviceClient)
    return try await getHousehold()
  }
  
  public func getHousehold() async throws -> Household {
    return try await loginService.getHousehold()
  }

  public func registeredDevice() async -> Device? {
    await deviceStore.registration()
  }

  // MARK: Device registration

  /// Runs `operation` with this installation's device, registering first when no registration
  /// is stored. If the platform no longer knows the device (the viewer removed it in the
  /// portal), registers again with the same serial and retries once.
  private func withRegisteredDevice<T>(_ operation: (Device) async throws -> T) async throws -> T {
    let device = try await ensureRegistered()
    do {
      return try await operation(device)
    } catch AuthError.deviceNotRegistered {
      await deviceStore.clearRegistration()
      let replacement = try await ensureRegistered()
      return try await operation(replacement)
    }
  }

  private func ensureRegistered() async throws -> Device {
    if let stored = await deviceStore.registration() {
      return stored
    }
    let serial = await deviceStore.serial()
    let clientToken = try await configService.getClientToken()
    let device = try await deviceService.register(profile: profile, serial: serial, clientToken: clientToken.access_token)
    await deviceStore.save(device)
    return device
  }

  /// Persists a grant response, overwriting only the fields the platform actually returned,
  /// and records the issuing client so refreshes go through the same one.
  private func store(_ tokens: AccessToken, issuedTo client: ClientIdentity) async {
    await tokenStore.save(accessToken: tokens.access_token, refreshToken: tokens.refresh_token)
    await tokenStore.saveIssuer(client)
    if let streamKey = tokens.stream_key, let streamUn = tokens.stream_un {
      await tokenStore.saveStreamKeys(streamKey: streamKey, streamUn: streamUn)
    }
  }
}
