import SwiftUI
import EONKit

// MARK: - Button styles

/// Text actions, chips and rows use the system's Liquid Glass button styles (`.glass` and
/// `.glassProminent`): the platform draws the platter, the focus lift and the pressed state, so
/// controls here look and move like controls everywhere else on tvOS. Only content — artwork
/// cards and the packed guide grid — keeps a custom focus treatment, built on the standard
/// focus APIs. Everything else that floats over content is glass too; see `glassPanel` and
/// `glassPill` below.

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

// MARK: - Glass

/// The app's own glass, for whatever floats over content without being a control: badges and
/// logos on artwork, panels and sheets, the guide's time ruler. Controls use the system button
/// styles, which draw their own. Both sample what lies beneath them, so the aurora and the
/// artwork show through the whole interface the way they show through the sidebar.
///
/// Cards keep their words on the canvas beneath the artwork, the way the system TV app's
/// episode cards do; only the focused card's caption settles onto a glass panel (`CardCaption`
/// in Cards.swift). The packed guide cells stay opaque, and nothing glass is laid over other
/// glass except the controls inside a panel and the badges on a card's artwork.
extension View {
  /// A panel: a sign-in form, an account card, a sheet in the player.
  func glassPanel(cornerRadius: CGFloat = Theme.panelRadius) -> some View {
    glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  /// A pill over artwork: a badge, a tag, a time. `prominent` tints it white for the rare
  /// emphasised state, the way the prominent button style does.
  func glassPill(prominent: Bool = false) -> some View {
    glassEffect(prominent ? .regular.tint(.white) : .regular, in: Capsule())
  }
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

/// Marks live television: a glass pill with the one saturated cue in the system, a red dot.
/// The full-size badge breathes; the compact one used on cards stays still.
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
    .glassPill()
    .onAppear {
      guard !compact, !calm else { return }
      withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
    }
  }
}

/// Small uppercase label on a glass pill. `solid` turns the pill white for the rare emphasised
/// state.
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
      .glassPill(prominent: solid)
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
/// The highlight is a Core Animation sweep over a gradient layer, so it runs in the render
/// server. A SwiftUI animation here — even one handed a whole sweep at a time — keeps the display
/// link firing and the screen redrawing on every frame for as long as a skeleton is on screen,
/// and a guide row that hasn't loaded yet shows a dozen at once while the viewer moves down.
struct SkeletonBlock: View {
  var cornerRadius: CGFloat = Theme.tileRadius
  @Environment(\.prefersCalmInterface) private var calm

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(Color.white.opacity(0.07))
      .overlay {
        if !calm {
          ShimmerSweep()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
      }
  }
}

/// A soft highlight that crosses its bounds every 1.8 seconds, snaps back and goes again.
private struct ShimmerSweep: UIViewRepresentable {
  func makeUIView(context: Context) -> ShimmerSweepView { ShimmerSweepView() }
  func updateUIView(_ view: ShimmerSweepView, context: Context) {}
}

final class ShimmerSweepView: UIView {
  private static let animationKey = "sweep"
  private let highlight = CAGradientLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    clipsToBounds = true
    highlight.colors = [UIColor.clear.cgColor, UIColor.white.withAlphaComponent(0.10).cgColor, UIColor.clear.cgColor]
    highlight.startPoint = CGPoint(x: 0, y: 0.5)
    highlight.endPoint = CGPoint(x: 1, y: 0.5)
    layer.addSublayer(highlight)
    // Core Animation drops animations while the app is in the background.
    NotificationCenter.default.addObserver(
      self, selector: #selector(restartSweep), name: UIApplication.didBecomeActiveNotification, object: nil
    )
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("ShimmerSweepView is created in code") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let width = bounds.width * 0.6
    let frame = CGRect(x: -width, y: 0, width: width, height: bounds.height)
    guard highlight.frame != frame else { return }
    highlight.frame = frame
    restartSweep()
  }

  @objc private func restartSweep() {
    highlight.removeAnimation(forKey: Self.animationKey)
    guard bounds.width > 0 else { return }
    let sweep = CABasicAnimation(keyPath: "transform.translation.x")
    sweep.fromValue = 0
    sweep.toValue = bounds.width + highlight.bounds.width
    sweep.duration = 1.8
    sweep.repeatCount = .infinity
    sweep.timingFunction = CAMediaTimingFunction(name: .linear)
    highlight.add(sweep, forKey: Self.animationKey)
  }
}

// MARK: - Status

/// The symbol above a status message, on a glass disc.
struct StatusGlyph: View {
  let symbol: String
  @ScaledMetric(relativeTo: .title) private var diameter: CGFloat = 150

  var body: some View {
    Image(systemName: symbol)
      .font(.title.weight(.light))
      .foregroundStyle(Theme.textSecondary)
      .frame(width: diameter, height: diameter)
      .glassEffect(in: Circle())
  }
}

/// Full-bleed empty, error and offline states with an optional primary action.
struct StatusView: View {
  let symbol: String
  let title: String
  let message: String
  var actionTitle: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: 24) {
      StatusGlyph(symbol: symbol)
        .padding(.bottom, 8)
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

/// The fill behind a screen, in the manner of the system TV app's show pages: a heavily blurred,
/// darkened wash of the featured artwork that colours the whole screen, brighter towards the top
/// and settling into deep shadow at the foot without ever going flat black. The aurora drifts
/// beneath it and carries the canvas on its own where there is no artwork; while artwork is up
/// it steps back so its bands don't cut through the wash. The wash cross-fades when the
/// featured image changes. When the system prefers a calmer interface the aurora holds still and
/// the blurred artwork is skipped, which is the costliest layer on screen.
///
/// The artwork only follows `url` once it has held still for a moment, so running focus along a
/// shelf doesn't start a full-screen crossfade on every card. The blur is applied to the artwork
/// at its native size and the result scaled up to fill the screen, which reads the same as
/// blurring the screen-sized image and costs a small fraction of the pixels.
///
/// `intensity` is how much of the artwork's own colour comes through: 0.4 on Home, where the
/// hero follows focus and the wash should stay a backdrop, up to 0.7 on a details screen that
/// is about one programme. The wash is composited over the grey canvas rather than black, so a
/// typical programme still lands around a fifth of full brightness, where the TV app sits.
struct AmbientBackdrop: View {
  let url: URL?
  var intensity: Double = 0.4
  @Environment(\.prefersCalmInterface) private var calm
  @State private var shownURL: URL?

  /// How long the featured artwork must stay the same before the backdrop takes it on.
  static let settleDelay: Duration = .milliseconds(320)

  private var showsArtwork: Bool { shownURL != nil && !calm }

  var body: some View {
    ZStack {
      Theme.backgroundGradient
      DriftingAurora(seed: 0, intensity: 0.45)
        .opacity(showsArtwork ? 0.3 : 1)
      if let shownURL, !calm {
        BlurredArtwork(url: shownURL)
          .id(shownURL)
          .transition(.opacity)
          .opacity(min(0.6, intensity * 1.4))
      }
      // A gentle vignette towards the foot, where the shelves run; never flat black.
      LinearGradient(
        stops: [
          .init(color: .black.opacity(0), location: 0),
          .init(color: .black.opacity(0.12), location: 0.5),
          .init(color: .black.opacity(0.28), location: 1),
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
        .blur(radius: 28)
        .saturation(0.85)
        .brightness(0.05)
        .scaleEffect(scale)
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .allowsHitTesting(false)
  }
}

// MARK: - Channel logo

/// Channel logo on a small glass platter so light logos always read against artwork.
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
    .glassEffect(platter ? .regular : .identity, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
