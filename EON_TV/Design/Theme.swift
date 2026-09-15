import SwiftUI

/// Design tokens for EON TV, drawn from the mark: a black canvas, white type, and one spectrum
/// line that carries every accent. Every screen draws from this one vocabulary so the product
/// reads as a single system rather than a set of API screens.
///
/// Controls follow the platform: buttons, chips and fields use the system's Liquid Glass styles so
/// focus looks and moves the way it does everywhere else on tvOS, and text uses the platform text
/// styles so it follows the viewer's Text Size setting (system-wide on tvOS 27).
enum Theme {
  // MARK: Colour

  static let background = Color.black
  static let backgroundElevated = Color(white: 0.08)
  static let surface = Color.white.opacity(0.06)
  static let surfaceStrong = Color.white.opacity(0.13)
  static let stroke = Color.white.opacity(0.12)
  static let strokeStrong = Color.white.opacity(0.34)

  static let textPrimary = Color.white
  static let textSecondary = Color.white.opacity(0.68)
  static let textTertiary = Color.white.opacity(0.42)
  static let textOnFocus = Color.black

  /// Emphasis is white; the only colour in the system comes from the spectrum.
  static let accent = Color.white
  /// The single saturated cue outside the spectrum: the dot that marks live television.
  static let live = Color(red: 1.0, green: 0.24, blue: 0.36)
  static let warning = Color(red: 1.0, green: 0.76, blue: 0.32)
  /// The teal that lights the aurora imagery; used only as a soft halo behind focused artwork.
  static let glow = Color(red: 0.18, green: 0.90, blue: 0.84)

  static var spectrum: LinearGradient {
    LinearGradient(gradient: spectrumGradient, startPoint: .leading, endPoint: .trailing)
  }

  static var spectrumFaded: LinearGradient {
    LinearGradient(gradient: spectrumFadedGradient, startPoint: .leading, endPoint: .trailing)
  }

  static var spectrumVertical: LinearGradient {
    LinearGradient(gradient: spectrumGradient, startPoint: .top, endPoint: .bottom)
  }

  static var accentGradient: LinearGradient { spectrum }

  static var backgroundGradient: LinearGradient {
    LinearGradient(colors: [.black, Color(white: 0.035)], startPoint: .top, endPoint: .bottom)
  }

  static var spectrumGradient: Gradient { gradient(BrandGeometry.spectrum) }
  static var spectrumFadedGradient: Gradient { gradient(BrandGeometry.spectrumFaded) }

  private static func gradient(_ stops: [BrandGeometry.Stop]) -> Gradient {
    Gradient(stops: stops.map {
      .init(
        color: Color(red: Double($0.red), green: Double($0.green), blue: Double($0.blue), opacity: Double($0.alpha)),
        location: $0.location
      )
    })
  }

  // MARK: Layout

  /// The tvOS safe zone: 80 points at the sides, 60 at the top and bottom.
  static let screenMargin: CGFloat = 80
  static let verticalMargin: CGFloat = 60
  /// Breathing room above a screen's first line, clear of the collapsed sidebar indicator.
  static let contentTop: CGFloat = 48
  static let cardRadius: CGFloat = 14
  static let tileRadius: CGFloat = 12
  static let panelRadius: CGFloat = 20
  static let shelfSpacing: CGFloat = 44
  static let cardSpacing: CGFloat = 32
  /// Base widths at the default text size; views scale them with `@ScaledMetric` so a caption
  /// keeps roughly the same number of characters when the viewer enlarges text.
  static let programCardWidth: CGFloat = 400
  static let channelTileWidth: CGFloat = 300
  /// Artwork stops growing past this factor even when text keeps scaling; captions are allowed
  /// a second line instead, so shelves stay browsable at the largest accessibility sizes.
  static let maxArtworkScale: CGFloat = 1.6

  // MARK: Motion

  static let focusAnimation = Animation.smooth(duration: 0.24, extraBounce: 0)
  static let crossfade = Animation.easeInOut(duration: 0.3)
  static let backdropFade = Animation.easeInOut(duration: 0.8)
}

/// Type uses the tvOS text styles so every label scales with the viewer's Text Size setting.
/// Weights stay regular or heavier: light faces are hard to read from across the room.
///
/// tvOS default sizes: title 76 · title2 57 · title3 48 · headline 38 · body 29 · callout 31 ·
/// caption 25 · caption2 23 (the platform minimum).
extension Font {
  static let heroTitle = Font.title2.weight(.regular)
  static let heroMeta = Font.caption.weight(.regular)
  static let heroBody = Font.body.weight(.regular)
  static let screenTitle = Font.title3.weight(.regular)
  static let sectionTitle = Font.callout
  static let cardTitle = Font.caption
  static let cardMeta = Font.caption2.weight(.regular)
  static let badge = Font.caption2.weight(.semibold)
  static let guideCell = Font.caption
  static let guideRuler = Font.caption2
  static let channelNumber = Font.caption2.monospacedDigit()
}

extension EnvironmentValues {
  /// True when the system asks apps to spend less on decoration (tvOS 27), or when the viewer
  /// has Reduce Motion on. Ambient animation, shimmer and heavy blur step aside in either case.
  var prefersCalmInterface: Bool {
    if accessibilityReduceMotion { return true }
    if #available(tvOS 27, *) { return systemPrefersReducedResourceUsage }
    return false
  }
}
