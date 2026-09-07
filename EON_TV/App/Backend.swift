import Foundation

/// Everything the UI needs from the platform, assembled once per process from the SDK's
/// repositories. The app never talks to services directly; it goes through this seam.
struct Backend {
  let auth: AuthRepository
  let channels: ChannelsRepository
  let epg: EpgRepository
  let streaming: StreamingRepository
  /// Re-synchronises `ServerTime` with the platform clock.
  let syncClock: () async throws -> Void
  /// Whether credentials from a previous session are stored on this device.
  let hasStoredSession: () async -> Bool
  /// Forgets stored credentials and the device registration (the device serial is kept).
  let clearSession: () async -> Void
  let isDemo: Bool
}

/// Wires the SDK: network client → interceptor chain → provider discovery → services → repositories.
enum BackendFactory {
  /// CDN entry to use from the broker. The SDK's device registration is bound to this provider.
  static let providerIdentifier = "vivacom"
  private static let baseURLKey = "eon.platform.baseURL"

  static func makeLive() async throws -> Backend {
    // The SDK's cache interceptor captures `URLCache.shared`, so size it before building the chain.
    URLCache.shared = URLCache(
      memoryCapacity: 24 * 1024 * 1024,
      diskCapacity: 256 * 1024 * 1024,
      diskPath: "eon-api"
    )

    var interceptors: [Interceptor] = [HeadersInterceptor()]
    #if DEBUG
    interceptors.append(LoggingInterceptor())
    #endif
    let client = NetworkClient(interceptors: interceptors)
    let tokenStore = TokenStore()
    let deviceStore = DeviceStore()

    let configService = ConfigService(client: client)
    let baseURL = try await resolveBaseURL(using: configService)

    let loginService = LoginService(client: client, baseURL: baseURL)
    let deviceService = DeviceService(client: client, baseURL: baseURL)
    let channelsService = ChannelsService(client: client, baseURL: baseURL)
    let streamingService = StreamingService(client: client, baseURL: baseURL)
    let epgService = EpgService(client: client, baseURL: baseURL)

    // Auth must run before the cache on the way out (bearer token) and before it on the way
    // back (401 → refresh → retry) so only the final, authorised payload is ever cached.
    client.addInterceptor(interceptor: AuthInterceptor(tokenStore: tokenStore, loginService: loginService))
    client.addInterceptor(interceptor: CacheInterceptor())

    return Backend(
      auth: AuthRepositoryImpl(
        loginService: loginService,
        deviceService: deviceService,
        configService: configService,
        tokenStore: tokenStore,
        deviceStore: deviceStore,
        profile: DeviceProfile.appleTV
      ),
      channels: ChannelsRepositoryImpl(channelsService: channelsService),
      epg: EpgRepositoryImpl(epgService: epgService, streamingService: streamingService),
      streaming: StreamingRepositoryImpl(streamingService: streamingService, tokenStore: tokenStore, deviceStore: deviceStore),
      syncClock: { _ = try await streamingService.getTime() },
      // Tokens are only usable together with the device they were issued to; a session from
      // before device registration existed is treated as signed out.
      hasStoredSession: { await tokenStore.getAccessToken() != nil && deviceStore.registration() != nil },
      // Forget the registration too, but never the serial: the next sign-in registers again
      // and gets the same device back unless the provider removed it, which is exactly the
      // recovery the platform expects after a device is deleted in the portal.
      clearSession: { await tokenStore.clear(); await deviceStore.clearRegistration() },
      isDemo: false
    )
  }

  /// Uses the last known API host immediately for a fast launch and refreshes it quietly;
  /// asks the broker only when nothing is cached yet.
  private static func resolveBaseURL(using config: ConfigService) async throws -> String {
    if let cached = UserDefaults.standard.string(forKey: baseURLKey), !cached.isEmpty {
      Task { try? await discoverBaseURL(using: config) }
      return cached
    }
    return try await discoverBaseURL(using: config)
  }

  @discardableResult
  private static func discoverBaseURL(using config: ConfigService) async throws -> String {
    let token = try await config.getClientToken()
    let entries = try await config.cdnInfo(accessToken: token.access_token)
    guard let entry = entries.first(where: { $0.identifier == providerIdentifier }) ?? entries.first else {
      throw NetworkError.notConfigured
    }
    let host = entry.domains.baseApi.af31
    UserDefaults.standard.set(host, forKey: baseURLKey)
    return host
  }
}

/// Human-readable messages for the SDK's error surface.
enum ErrorPresenter {
  static func message(for error: Error, context: Context) -> String {
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
        return "You're offline. Check your network connection and try again."
      case .timedOut:
        return "EON TV is taking too long to respond. Please try again."
      case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
        return "EON TV can't be reached right now. Please try again in a moment."
      default:
        return "A network problem interrupted the request. Please try again."
      }
    }
    if let authError = error as? AuthError {
      switch authError {
      case .badCredentials:
        return "We couldn't sign you in. Check your username and password."
      case .deviceNotRegistered:
        return "This Apple TV isn't registered with your provider. Please try again."
      case .codeNotConfirmed:
        return "The code hasn't been confirmed yet."
      case .sessionExpired:
        return "Your session has expired. Please sign in again."
      case .grantNotAllowed:
        return "This way of signing in isn't available right now."
      case .httpStatus(429):
        return "Too many attempts. Please wait a moment and try again."
      case .httpStatus:
        return "EON TV couldn't complete the request. Please try again."
      case .platform(_, let description):
        return description.isEmpty ? "Something went wrong while talking to EON TV." : description
      }
    }
    if let networkError = error as? NetworkError {
      switch (networkError, context) {
      case (.decodingError, .signIn):
        return "We couldn't sign you in. Check your username and password."
      case (.decodingError, .session):
        return "Your session has expired. Please sign in again."
      case (.notConfigured, _):
        return "The service configuration couldn't be loaded."
      case (.missingParams, .signIn):
        return "Enter your username and password."
      default:
        return "Something went wrong while talking to EON TV."
      }
    }
    if let streamingError = error as? StreamingError {
      switch streamingError {
      case .missingData: return "This stream isn't available for your account right now."
      case .failToEncryptAES: return "The stream request couldn't be prepared."
      }
    }
    return "Something went wrong. Please try again."
  }

  enum Context {
    case signIn, session, content, playback
  }
}
