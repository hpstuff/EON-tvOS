import SwiftUI

extension AuroraGeometry.RGB {
  var color: Color { Color(red: Double(red), green: Double(green), blue: Double(blue)) }
}

extension AuroraGeometry.Palette {
  /// Near-black fill for small tiles: a hint of the palette in one corner, black in the other.
  var tileTint: LinearGradient {
    LinearGradient(
      colors: [deep.color.opacity(0.85), Color(white: 0.05)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

/// One wave band: a sine ridge with a body fading away beneath it.
struct AuroraBandShape: Shape {
  var baseline: CGFloat
  var amplitude: CGFloat
  var frequency: CGFloat
  var phase: CGFloat
  var thickness: CGFloat

  func path(in rect: CGRect) -> Path {
    Path(AuroraGeometry.band(in: rect, baseline: baseline, amplitude: amplitude, frequency: frequency, phase: phase, thickness: thickness))
  }
}

/// The bright edge of a wave.
struct AuroraRidgeShape: Shape {
  var baseline: CGFloat
  var amplitude: CGFloat
  var frequency: CGFloat
  var phase: CGFloat

  func path(in rect: CGRect) -> Path {
    Path(AuroraGeometry.ridge(in: rect, baseline: baseline, amplitude: amplitude, frequency: frequency, phase: phase))
  }
}

/// The aurora: two blurred wave bands and a bright ridge, drawn once into a layer and held
/// still. The `seed` picks the palette and the wave's shape, so tiles and placeholders differ.
/// `DriftingAurora` is the moving variant behind whole screens.
struct AuroraWaves: View {
  var seed: Int = 0
  var intensity: Double = 1
  var blurFraction: CGFloat = 0.08

  var body: some View {
    let palette = AuroraGeometry.palette(seed: seed)
    let accent = AuroraGeometry.palette(seed: seed + 1)
    let variant = CGFloat(abs(seed) % 13) / 13

    GeometryReader { proxy in
      let size = proxy.size
      let width = size.width * 1.35
      ZStack {
        AuroraBandShape(baseline: 0.48 + variant * 0.1, amplitude: 0.13, frequency: 1.0, phase: variant, thickness: 0.45)
          .fill(LinearGradient(
            colors: [palette.mid.color.opacity(0.9), palette.deep.color.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
          ))
        AuroraBandShape(baseline: 0.60 - variant * 0.1, amplitude: 0.10, frequency: 0.75, phase: variant + 0.4, thickness: 0.35)
          .fill(LinearGradient(
            colors: [accent.mid.color.opacity(0.75), accent.deep.color.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
          ))
          .blendMode(.screen)
        AuroraRidgeShape(baseline: 0.48 + variant * 0.1, amplitude: 0.13, frequency: 1.0, phase: variant)
          .stroke(palette.core.color.opacity(0.85), style: StrokeStyle(lineWidth: max(1.5, size.height * 0.012), lineCap: .round))
          .blendMode(.screen)
      }
      .frame(width: width, height: size.height)
      .blur(radius: size.height * blurFraction)
      .drawingGroup()
      .offset(x: -(width - size.width) / 2)
      .frame(width: size.width, height: size.height, alignment: .leading)
      .clipped()
    }
    .opacity(intensity)
    .allowsHitTesting(false)
  }
}

/// The aurora behind a whole screen, sliding slowly back and forth.
///
/// The motion is a Core Animation transform on a hosted copy of `AuroraWaves`, so it runs in the
/// render server. Animating the offset in SwiftUI instead kept the display link firing and the
/// screen redrawing on every frame for as long as the screen was up — on the guide, with its
/// hundreds of cells and glass chips, that was most of the main thread before a single press.
/// The aurora holds still when the viewer prefers reduced motion or the system asks for a calmer
/// interface.
struct DriftingAurora: UIViewRepresentable {
  var seed: Int = 0
  var intensity: Double = 1
  @Environment(\.prefersCalmInterface) private var calm

  func makeUIView(context: Context) -> DriftingAuroraView {
    DriftingAuroraView(waves: AuroraWaves(seed: seed, intensity: intensity))
  }

  func updateUIView(_ view: DriftingAuroraView, context: Context) {
    view.host.rootView = AuroraWaves(seed: seed, intensity: intensity)
    view.isDrifting = !calm
  }
}

final class DriftingAuroraView: UIView {
  /// The aurora is drawn this much wider than the screen; the drift covers the difference.
  static let overscan: CGFloat = 1.35
  static let period: CFTimeInterval = 18
  private static let animationKey = "drift"

  let host: UIHostingController<AuroraWaves>
  var isDrifting = true {
    didSet { if isDrifting != oldValue { updateDrift() } }
  }

  init(waves: AuroraWaves) {
    host = UIHostingController(rootView: waves)
    super.init(frame: .zero)
    host.view.backgroundColor = .clear
    isUserInteractionEnabled = false
    clipsToBounds = true
    addSubview(host.view)
    // Core Animation drops animations while the app is in the background.
    NotificationCenter.default.addObserver(
      self, selector: #selector(updateDrift), name: UIApplication.didBecomeActiveNotification, object: nil
    )
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("DriftingAuroraView is created in code") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let size = CGSize(width: bounds.width * Self.overscan, height: bounds.height)
    guard host.view.bounds.size != size else { return }
    host.view.bounds = CGRect(origin: .zero, size: size)
    host.view.center = CGPoint(x: size.width / 2, y: size.height / 2)
    updateDrift()
  }

  @objc private func updateDrift() {
    let layer = host.view.layer
    layer.removeAnimation(forKey: Self.animationKey)
    let travel = bounds.width * (Self.overscan - 1)
    guard isDrifting, travel > 0 else { return }
    let drift = CABasicAnimation(keyPath: "transform.translation.x")
    drift.fromValue = 0
    drift.toValue = -travel
    drift.duration = Self.period
    drift.autoreverses = true
    drift.repeatCount = .infinity
    drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(drift, forKey: Self.animationKey)
  }
}
