import Foundation

/// The EON brand this build talks to. It is fixed at build time by the `EON_*` settings in
/// Config/App.xcconfig and reaches the app through Info.plist.
struct BrandConfig {
  /// Identifier from the broker's `v2/brands`, such as `vivacom` or `telemach-si`.
  let identifier: String
  /// Language the platform names categories in when the Apple TV is set to it.
  let language: String
  /// Code sign-in needs a Smart TV client issued for this brand.
  let supportsCodeSignIn: Bool

  static let current = BrandConfig(bundle: .main)

  init(bundle: Bundle) {
    func value(_ key: String) -> String {
      guard let value = bundle.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
        preconditionFailure("\(key) is missing from Info.plist; the EON_* settings come from Config/App.xcconfig.")
      }
      return value
    }
    identifier = value("EONBrand")
    language = value("EONLanguage")
    supportsCodeSignIn = value("EONCodeSignIn") == "YES"
  }
}
