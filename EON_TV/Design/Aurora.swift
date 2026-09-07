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

/// The aurora: two blurred wave bands and a bright ridge, drawn once into a layer. `drifting`
/// slides that layer slowly back and forth, which costs a transform per frame rather than a redraw.
/// The `seed` picks the palette and the wave's shape, so tiles and placeholders differ.
struct AuroraWaves: View {
  var seed: Int = 0
  var intensity: Double = 1
  var blurFraction: CGFloat = 0.08
  var drifting = false

  @State private var drifted = false

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
      .offset(x: drifting ? (drifted ? -(width - size.width) : 0) : -(width - size.width) / 2)
      .frame(width: size.width, height: size.height, alignment: .leading)
      .clipped()
    }
    .opacity(intensity)
    .allowsHitTesting(false)
    .onAppear {
      guard drifting else { return }
      withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drifted = true }
    }
  }
}
