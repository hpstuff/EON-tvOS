import SwiftUI

// MARK: - Button styles

/// Text actions, chips and rows use the system's Liquid Glass button styles (`.glass` and
/// `.glassProminent`): the platform draws the platter, the focus lift and the pressed state, so
/// controls here look and move like controls everywhere else on tvOS. Only content — artwork
/// cards and the packed guide grid — keeps a custom focus treatment, built on the standard
/// focus APIs.

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
        // Hundreds of cells share a grid; only the focused one carries a shadow, so the rest
        // cost nothing beyond their own fill.
        .background {
          if isFocused {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(Color.black.opacity(0.5))
              .blur(radius: 18)
              .offset(y: 10)
              .transition(.opacity)
          }
        }
        .scaleEffect(isFocused ? 1.02 : 1)
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

extension ButtonStyle where Self == GuideCellButtonStyle {
  static var guideCell: GuideCellButtonStyle { GuideCellButtonStyle() }
}

extension ButtonStyle where Self == BareButtonStyle {
  static var bare: BareButtonStyle { BareButtonStyle() }
}

// MARK: - Chips

/// Label for a filter chip inside a glass button. Selection is shown in the label — heavier
/// type and a short run of the spectrum — so the platter and focus stay the system's.
struct FilterChipLabel: View {
  let title: String
  var symbol: String? = nil
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 10) {
      if let symbol {
        Image(systemName: symbol)
          .font(.caption2.weight(.semibold))
      }
      Text(title)
        .font(.caption.weight(isSelected ? .semibold : .regular))
    }
    .lineLimit(1)
    .padding(.bottom, 6)
    .overlay(alignment: .bottom) {
      SpectrumLine(faded: false, height: 3)
        .clipShape(Capsule())
        .opacity(isSelected ? 1 : 0)
    }
    .animation(Theme.focusAnimation, value: isSelected)
  }
}

// MARK: - Badges

/// Marks live television: a monochrome pill with the one saturated cue in the system, a red
/// dot. The full-size badge breathes; the compact one used on cards stays still.
struct LiveBadge: View {
  var compact = false
  @State private var breathing = false
  @Environment(\.prefersCalmInterface) private var calm
  @ScaledMetric(relativeTo: .caption2) private var dot: CGFloat = 10

  var body: some View {
    HStack(spacing: compact ? 7 : 9) {
      Circle()
        .fill(Theme.live)
        .frame(width: compact ? dot * 0.8 : dot, height: compact ? dot * 0.8 : dot)
        .opacity(breathing ? 0.5 : 1)
      Text("LIVE")
        .font(.badge)
        .kerning(1.6)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, compact ? 10 : 14)
    .padding(.vertical, compact ? 5 : 7)
    .background(Capsule().fill(Color.black.opacity(0.55)))
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
    .onAppear {
      guard !compact, !calm else { return }
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
      .lineLimit(1)
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
          .font(.caption.weight(.regular))
          .foregroundStyle(Theme.textTertiary)
      }
      Spacer()
    }
  }
}

// MARK: - Skeleton

/// Shimmering placeholder used while artwork, cards or guide rows are still loading. The shimmer
/// pauses when the system prefers a calmer, cheaper interface.
///
/// The highlight is one animation handed to the render server per sweep, not a timeline that
/// rebuilds the view thirty times a second: a loading guide shows a hundred of these at once,
/// and rebuilding them all every frame is what made the grid stutter.
struct SkeletonBlock: View {
  var cornerRadius: CGFloat = Theme.tileRadius
  @Environment(\.prefersCalmInterface) private var calm

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(Color.white.opacity(0.07))
      .overlay {
        if !calm {
          PhaseAnimator([false, true]) { sweeping in
            GeometryReader { proxy in
              LinearGradient(
                colors: [.clear, Color.white.opacity(0.10), .clear],
                startPoint: .leading,
                endPoint: .trailing
              )
              .frame(width: proxy.size.width * 0.6)
              .offset(x: sweeping ? proxy.size.width : -proxy.size.width * 0.6)
            }
          } animation: { sweeping in
            // Sweep across, then snap back out of sight and go again.
            sweeping ? .linear(duration: 1.8) : .linear(duration: 0.01)
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
        .font(.title.weight(.light))
        .foregroundStyle(Theme.textSecondary)
      Text(title)
        .font(.headline.weight(.regular))
        .foregroundStyle(Theme.textPrimary)
        .multilineTextAlignment(.center)
      Text(message)
        .font(.body.weight(.regular))
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 900)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.glassProminent)
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
/// When the system prefers a calmer interface the aurora holds still and the blurred artwork is
/// skipped, which is the costliest layer on screen.
///
/// The artwork only follows `url` once it has held still for a moment, so running focus along a
/// shelf doesn't start a full-screen crossfade on every card. The blur is applied to the artwork
/// at its native size and the result scaled up to fill the screen, which reads the same as
/// blurring the screen-sized image and costs a small fraction of the pixels.
struct AmbientBackdrop: View {
  let url: URL?
  var intensity: Double = 0.4
  @Environment(\.prefersCalmInterface) private var calm
  @State private var shownURL: URL?

  /// How long the featured artwork must stay the same before the backdrop takes it on.
  static let settleDelay: Duration = .milliseconds(320)

  var body: some View {
    ZStack {
      Theme.backgroundGradient
      AuroraWaves(seed: 0, intensity: 0.45, drifting: true)
      if let shownURL, !calm {
        BlurredArtwork(url: shownURL)
          .id(shownURL)
          .transition(.opacity)
          .opacity(intensity * 0.5)
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
    .animation(Theme.backdropFade, value: shownURL)
    .ignoresSafeArea()
    .task(id: url) {
      guard shownURL != nil else {
        shownURL = url
        return
      }
      try? await Task.sleep(for: Self.settleDelay)
      guard !Task.isCancelled else { return }
      shownURL = url
    }
  }
}

/// Artwork blurred at the platform's XL rendition size and stretched over the whole screen.
private struct BlurredArtwork: View {
  let url: URL
  private static let renditionSize = CGSize(width: 480, height: 270)

  var body: some View {
    GeometryReader { proxy in
      let size = Self.renditionSize
      let scale = max(proxy.size.width / size.width, proxy.size.height / size.height) * 1.3
      RemoteImage(url: url) { Color.clear }
        .frame(width: size.width, height: size.height)
        .clipped()
        .blur(radius: 24)
        .saturation(0.9)
        .scaleEffect(scale)
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .allowsHitTesting(false)
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
