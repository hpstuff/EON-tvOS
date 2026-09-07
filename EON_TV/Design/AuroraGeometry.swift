import CoreGraphics
import Foundation

/// Luminous wave bands – the aurora that drifts behind screens and fills artwork placeholders –
/// described once so SwiftUI views and the CoreGraphics demo renderer draw the same thing.
///
/// Three palettes come from the brand imagery: teal, violet and deep blue. A band is a sine
/// ridge with a body beneath it; a ridge alone is stroked as the bright edge of a wave.
nonisolated enum AuroraGeometry {
  struct RGB {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
      self.red = red
      self.green = green
      self.blue = blue
    }

    func cgColor(alpha: CGFloat) -> CGColor {
      CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
  }

  struct Palette {
    /// The bright edge of the wave.
    let core: RGB
    /// The glowing body.
    let mid: RGB
    /// The dark mass the wave fades into.
    let deep: RGB
  }

  static let teal = Palette(core: RGB(0.20, 0.96, 0.88), mid: RGB(0.07, 0.62, 0.70), deep: RGB(0.02, 0.20, 0.27))
  static let violet = Palette(core: RGB(0.88, 0.40, 1.00), mid: RGB(0.52, 0.18, 0.84), deep: RGB(0.17, 0.05, 0.32))
  static let blue = Palette(core: RGB(0.42, 0.54, 1.00), mid: RGB(0.17, 0.24, 0.82), deep: RGB(0.05, 0.08, 0.34))
  static let palettes = [teal, violet, blue]

  static func palette(seed: Int) -> Palette {
    palettes[abs(seed) % palettes.count]
  }

  /// Height of the ridge at `x`, as a fraction of the rect's height. A second, faster sine gives
  /// the wave its uneven, natural silhouette.
  private static func ridgeFraction(at x: CGFloat, width: CGFloat, baseline: CGFloat, amplitude: CGFloat, frequency: CGFloat, phase: CGFloat) -> CGFloat {
    let t = x / max(1, width)
    let primary = sin((t * frequency + phase) * 2 * .pi)
    let detail = sin((t * frequency * 2.3 + phase * 1.7) * 2 * .pi)
    return baseline + amplitude * (primary + 0.3 * detail)
  }

  /// The bright edge of a wave, as an open polyline.
  static func ridge(in rect: CGRect, baseline: CGFloat, amplitude: CGFloat, frequency: CGFloat, phase: CGFloat, samples: Int = 64) -> CGPath {
    let path = CGMutablePath()
    for index in 0...samples {
      let x = rect.width * CGFloat(index) / CGFloat(samples)
      let fraction = ridgeFraction(at: x, width: rect.width, baseline: baseline, amplitude: amplitude, frequency: frequency, phase: phase)
      let point = CGPoint(x: rect.minX + x, y: rect.minY + rect.height * fraction)
      if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    return path
  }

  /// A wave band: the ridge on top, and a body below it whose depth swells along the width.
  static func band(in rect: CGRect, baseline: CGFloat, amplitude: CGFloat, frequency: CGFloat, phase: CGFloat, thickness: CGFloat, samples: Int = 64) -> CGPath {
    let path = CGMutablePath()
    var bottom: [CGPoint] = []
    for index in 0...samples {
      let x = rect.width * CGFloat(index) / CGFloat(samples)
      let fraction = ridgeFraction(at: x, width: rect.width, baseline: baseline, amplitude: amplitude, frequency: frequency, phase: phase)
      let top = CGPoint(x: rect.minX + x, y: rect.minY + rect.height * fraction)
      if index == 0 { path.move(to: top) } else { path.addLine(to: top) }
      let swell = 1 + 0.35 * sin((x / max(1, rect.width) * frequency * 0.7 + phase) * 2 * .pi)
      bottom.append(CGPoint(x: top.x, y: top.y + rect.height * thickness * swell))
    }
    for point in bottom.reversed() {
      path.addLine(to: point)
    }
    path.closeSubpath()
    return path
  }
}
