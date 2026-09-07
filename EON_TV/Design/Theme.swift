import SwiftUI

/// Design tokens for EON TV, drawn from the mark: a black canvas, thin white type, and one
/// spectrum line that carries every accent. Every screen draws from this one vocabulary so the
/// product reads as a single system rather than a set of API screens.
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

  static let screenMargin: CGFloat = 80
  /// Breathing room between the tab bar and the first line of content.
  static let contentTop: CGFloat = 64
  static let cardRadius: CGFloat = 14
  static let tileRadius: CGFloat = 12
  static let panelRadius: CGFloat = 20
  static let shelfSpacing: CGFloat = 44
  static let cardSpacing: CGFloat = 32
  static let programCardWidth: CGFloat = 400
  static let channelTileWidth: CGFloat = 300

  // MARK: Motion

  static let focusAnimation = Animation.smooth(duration: 0.24, extraBounce: 0)
  static let crossfade = Animation.easeInOut(duration: 0.3)
  static let backdropFade = Animation.easeInOut(duration: 0.8)
}

/// Type follows the mark: light, open display faces, with medium weights only where text has
/// to be read at a glance from across the room.
extension Font {
  static let heroTitle = Font.system(size: 58, weight: .light)
  static let heroMeta = Font.system(size: 26, weight: .regular)
  static let heroBody = Font.system(size: 26, weight: .regular)
  static let screenTitle = Font.system(size: 44, weight: .light)
  static let sectionTitle = Font.system(size: 32, weight: .regular)
  static let cardTitle = Font.system(size: 25, weight: .medium)
  static let cardMeta = Font.system(size: 21, weight: .regular)
  static let button = Font.system(size: 25, weight: .medium)
  static let badge = Font.system(size: 17, weight: .semibold)
  static let guideCell = Font.system(size: 24, weight: .medium)
  static let guideRuler = Font.system(size: 21, weight: .medium)
  static let channelNumber = Font.system(size: 22, weight: .medium).monospacedDigit()
}
