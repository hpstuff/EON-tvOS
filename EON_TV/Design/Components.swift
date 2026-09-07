import SwiftUI

// MARK: - Button styles

/// Artwork cards: lift, deepen the shadow and let the label brighten when focused.
struct ArtworkCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    StyledLabel(configuration: configuration)
  }

  private struct StyledLabel: View {
    let configuration: Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
      configuration.label
        .scaleEffect(isFocused ? 1.06 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.6 : 0.25), radius: isFocused ? 34 : 14, y: isFocused ? 22 : 8)
        .brightness(configuration.isPressed ? -0.06 : 0)
        .animation(Theme.focusAnimation, value: isFocused)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
  }
}

/// Text actions and chips: a hairline capsule, like the strokes of the mark, that becomes a
/// solid white platter when focused. Prominent buttons carry a stronger outline so the primary
/// action reads at rest.
struct PillButtonStyle: ButtonStyle {
  var prominent = false

  func makeBody(configuration: Configuration) -> some View {
    StyledLabel(configuration: configuration, prominent: prominent)
  }

  private struct StyledLabel: View {
    let configuration: Configuration
    let prominent: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
      configuration.label
        .font(.button)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(isFocused ? Theme.textOnFocus : .white)
        .padding(.horizontal, 30)
        .padding(.vertical, 16)
        .background {
          Capsule().fill(isFocused ? Color.white : (prominent ? Theme.surfaceStrong : Theme.surface))
        }
        .overlay {
          Capsule().strokeBorder(isFocused ? Color.clear : (prominent ? Theme.strokeStrong : Theme.stroke), lineWidth: 1.5)
        }
        .scaleEffect(isFocused ? 1.05 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 20, y: 12)
        .opacity(configuration.isPressed ? 0.85 : 1)
        .animation(Theme.focusAnimation, value: isFocused)
    }
  }
}

/// Programme cells in the guide grid: no scaling (cells are packed), a white platter on focus.
struct GuideCellButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    StyledLabel(configuration: configuration)
  }

  private struct StyledLabel: View {
    let configuration: Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
      configuration.label
        .environment(\.guideCellFocused, isFocused)
        .scaleEffect(isFocused ? 1.02 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 18, y: 10)
        .zIndex(isFocused ? 1 : 0)
        .animation(Theme.focusAnimation, value: isFocused)
    }
  }
}

private struct GuideCellFocusedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var guideCellFocused: Bool {
    get { self[GuideCellFocusedKey.self] }
    set { self[GuideCellFocusedKey.self] = newValue }
  }
}

/// Passes the label through untouched; the label draws its own focus state.
struct BareButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.85 : 1)
  }
}

extension ButtonStyle where Self == ArtworkCardButtonStyle {
  static var artworkCard: ArtworkCardButtonStyle { ArtworkCardButtonStyle() }
}

extension ButtonStyle where Self == PillButtonStyle {
  static var pill: PillButtonStyle { PillButtonStyle() }
  static var prominentPill: PillButtonStyle { PillButtonStyle(prominent: true) }
}

extension ButtonStyle where Self == GuideCellButtonStyle {
  static var guideCell: GuideCellButtonStyle { GuideCellButtonStyle() }
}

extension ButtonStyle where Self == BareButtonStyle {
  static var bare: BareButtonStyle { BareButtonStyle() }
}

// MARK: - Badges

/// Marks live television: a monochrome pill with the one saturated cue in the system, a red
/// dot. The full-size badge breathes; the compact one used on cards stays still.
struct LiveBadge: View {
  var compact = false
  @State private var breathing = false

  var body: some View {
    HStack(spacing: compact ? 7 : 9) {
      Circle()
        .fill(Theme.live)
        .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
        .opacity(breathing ? 0.5 : 1)
      Text("LIVE")
        .font(compact ? .system(size: 15, weight: .semibold) : .badge)
        .kerning(1.6)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, compact ? 10 : 14)
    .padding(.vertical, compact ? 5 : 7)
    .background(Capsule().fill(Color.black.opacity(0.55)))
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
    .onAppear {
      guard !compact else { return }
      withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
    }
  }
}

/// Small uppercase label. Monochrome by default; `solid` inverts it for the rare emphasised state.
struct Tag: View {
  let text: String
  var solid = false

  var body: some View {
    Text(text)
      .font(.badge)
      .kerning(1.4)
      .foregroundStyle(solid ? Theme.textOnFocus : .white)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Capsule().fill(solid ? Color.white : Color.black.opacity(0.5)))
      .overlay(Capsule().strokeBorder(Color.white.opacity(solid ? 0 : 0.25), lineWidth: 1))
  }
}

// MARK: - Progress

/// Progress as a reveal of the spectrum. The colours are fixed to positions along the track, so
/// a bar that fills up walks through the line the way the mark does.
struct ProgressBar: View {
  let progress: Double
  var track: Color = Color.white.opacity(0.16)
  var height: CGFloat = 6

  var body: some View {
    GeometryReader { proxy in
      let fraction = min(1, max(0, progress))
      ZStack(alignment: .leading) {
        Capsule().fill(track)
        Capsule()
          .fill(Theme.spectrum)
          .mask(alignment: .leading) {
            Capsule().frame(width: max(height, proxy.size.width * fraction))
          }
      }
    }
    .frame(height: height)
    .animation(.linear(duration: 0.6), value: progress)
  }
}

// MARK: - Section header

struct SectionHeader: View {
  let title: String
  var subtitle: String? = nil

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 18) {
      Text(title)
        .font(.sectionTitle)
        .kerning(0.4)
        .foregroundStyle(Theme.textPrimary)
      if let subtitle {
        Text(subtitle)
          .font(.system(size: 23, weight: .regular))
          .foregroundStyle(Theme.textTertiary)
      }
      Spacer()
    }
  }
}

// MARK: - Skeleton

/// Shimmering placeholder used while artwork, cards or guide rows are still loading.
struct SkeletonBlock: View {
  var cornerRadius: CGFloat = Theme.tileRadius

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
      let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color.white.opacity(0.07))
        .overlay {
          GeometryReader { proxy in
            LinearGradient(
              colors: [.clear, Color.white.opacity(0.10), .clear],
              startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.6)
            .offset(x: -proxy.size.width * 0.6 + (proxy.size.width * 1.6) * phase)
          }
          .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
  }
}

// MARK: - Status

/// Full-bleed empty, error and offline states with an optional primary action.
struct StatusView: View {
  let symbol: String
  let title: String
  let message: String
  var actionTitle: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: symbol)
        .font(.system(size: 72, weight: .ultraLight))
        .foregroundStyle(Theme.textSecondary)
      Text(title)
        .font(.system(size: 40, weight: .regular))
        .foregroundStyle(Theme.textPrimary)
      Text(message)
        .font(.system(size: 26))
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 760)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.prominentPill)
          .padding(.top, 12)
      }
    }
    .padding(60)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Ambient backdrop

/// The black canvas with a faint, blurred trace of the featured artwork behind a screen; it
/// cross-fades when the featured image changes and always settles back into black at the foot.
struct AmbientBackdrop: View {
  let url: URL?
  var intensity: Double = 0.4

  var body: some View {
    ZStack {
      Theme.backgroundGradient
      AuroraWaves(seed: 0, intensity: 0.45, drifting: true)
      if let url {
        RemoteImage(url: url) { Color.clear }
          .id(url)
          .transition(.opacity)
          .blur(radius: 100)
          .saturation(0.9)
          .opacity(intensity * 0.5)
          .scaleEffect(1.3)
      }
      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.35), location: 0),
          .init(color: .black.opacity(0.75), location: 0.55),
          .init(color: .black, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .animation(Theme.backdropFade, value: url)
    .ignoresSafeArea()
  }
}

// MARK: - Channel logo

/// Channel logo on a subtle platter so light logos always read against artwork.
struct ChannelLogo: View {
  let channel: Channel
  var height: CGFloat = 44
  var platter = true

  var body: some View {
    RemoteImage(url: channel.logoURL, contentMode: .fit) {
      Text(channel.shortName)
        .font(.system(size: height * 0.42, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, 6)
    }
    .frame(height: height)
    .frame(minWidth: height * 1.2, maxWidth: height * 2.2)
    .padding(.horizontal, platter ? 10 : 0)
    .padding(.vertical, platter ? 6 : 0)
    .background {
      if platter {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.black.opacity(0.5))
      }
    }
  }
}
