import CoreGraphics
import Foundation

/// The EON mark described once, in units of the E and N cap height, so the app (SwiftUI) and
/// the icon generator (CoreGraphics on macOS) draw exactly the same thing at any size.
///
/// Three thin letterforms – a bracketed E, a large ring for the O and an N – share a centre
/// line and are sliced by a horizontal band. The spectrum line runs through that band and
/// fades out a little beyond the letters.
enum BrandGeometry {
  /// Stroke weight of every letter.
  static let stroke: CGFloat = 0.133
  static let eWidth: CGFloat = 0.87
  static let ringCenter = CGPoint(x: 2.449, y: 0.505)
  static let ringRadius: CGFloat = 0.969
  static let nLeft: CGFloat = 3.98
  static let nWidth: CGFloat = 1.0
  /// Horizontal footprint of the N's diagonal, chosen so its perpendicular weight matches the stems.
  static let diagonalWidth: CGFloat = 0.165
  /// The slice through all three letters, measured from the cap line.
  static let bandTop: CGFloat = 0.357
  static let bandBottom: CGFloat = 0.663
  static let lineThickness: CGFloat = 0.14
  /// How far the spectrum line runs past the letters on each side while it fades out.
  static let lineOverhang: CGFloat = 0.77

  /// Left edge of the E to right edge of the N.
  static var letterSpan: CGFloat { nLeft + nWidth }
  /// Bounds of the whole mark in cap units: the line sets the width, the ring the height.
  static var unitSize: CGSize { CGSize(width: letterSpan + lineOverhang * 2, height: ringRadius * 2) }
  /// Distance from the top of the mark down to the cap line.
  static var capTop: CGFloat { ringRadius - ringCenter.y }
  static var letterLeft: CGFloat { lineOverhang }

  static func cap(forHeight height: CGFloat) -> CGFloat { height / unitSize.height }

  static func size(forHeight height: CGFloat) -> CGSize {
    let cap = cap(forHeight: height)
    return CGSize(width: unitSize.width * cap, height: height)
  }

  /// The letterforms without the slice. Fill with the even-odd rule: no two pieces overlap, and
  /// the O's inner ellipse punches the hole in the ring.
  static func letters(cap: CGFloat, origin: CGPoint = .zero) -> CGPath {
    let path = CGMutablePath()
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
      path.addRect(CGRect(
        x: origin.x + (letterLeft + x) * cap,
        y: origin.y + (capTop + y) * cap,
        width: width * cap,
        height: height * cap
      ))
    }

    // E: a stem with two arms; the band later removes the middle of the stem.
    rect(0, 0, stroke, 1)
    rect(stroke, 0, eWidth - stroke, stroke)
    rect(stroke, 1 - stroke, eWidth - stroke, stroke)

    // O: a ring.
    let center = CGPoint(
      x: origin.x + (letterLeft + ringCenter.x) * cap,
      y: origin.y + (capTop + ringCenter.y) * cap
    )
    for radius in [ringRadius, ringRadius - stroke] {
      path.addEllipse(in: CGRect(
        x: center.x - radius * cap,
        y: center.y - radius * cap,
        width: radius * 2 * cap,
        height: radius * 2 * cap
      ))
    }

    // N: two stems joined by a diagonal from the head of the left one to the foot of the right one.
    rect(nLeft, 0, stroke, 1)
    rect(nLeft + nWidth - stroke, 0, stroke, 1)
    let left = origin.x + (letterLeft + nLeft) * cap
    let top = origin.y + capTop * cap
    path.move(to: CGPoint(x: left + stroke * cap, y: top))
    path.addLine(to: CGPoint(x: left + (stroke + diagonalWidth) * cap, y: top))
    path.addLine(to: CGPoint(x: left + (nWidth - stroke) * cap, y: top + cap))
    path.addLine(to: CGPoint(x: left + (nWidth - stroke - diagonalWidth) * cap, y: top + cap))
    path.closeSubpath()

    return path
  }

  /// The slice, spanning the full width of the mark.
  static func band(cap: CGFloat, origin: CGPoint = .zero) -> CGRect {
    CGRect(
      x: origin.x,
      y: origin.y + (capTop + bandTop) * cap,
      width: unitSize.width * cap,
      height: (bandBottom - bandTop) * cap
    )
  }

  /// The spectrum line, centred in the slice.
  static func line(cap: CGFloat, origin: CGPoint = .zero) -> CGRect {
    let middle = capTop + (bandTop + bandBottom) / 2
    return CGRect(
      x: origin.x,
      y: origin.y + (middle - lineThickness / 2) * cap,
      width: unitSize.width * cap,
      height: lineThickness * cap
    )
  }

  // MARK: Spectrum

  struct Stop {
    let location: CGFloat
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
  }

  /// The colour run of the line, left to right.
  static let spectrum: [Stop] = [
    Stop(location: 0.00, red: 0.96, green: 0.18, blue: 0.72, alpha: 1), // magenta
    Stop(location: 0.16, red: 0.55, green: 0.24, blue: 0.95, alpha: 1), // violet
    Stop(location: 0.32, red: 0.18, green: 0.40, blue: 1.00, alpha: 1), // blue
    Stop(location: 0.48, red: 0.15, green: 0.78, blue: 0.96, alpha: 1), // cyan
    Stop(location: 0.62, red: 0.19, green: 0.88, blue: 0.50, alpha: 1), // green
    Stop(location: 0.76, red: 0.73, green: 0.91, blue: 0.24, alpha: 1), // yellow-green
    Stop(location: 0.88, red: 0.97, green: 0.82, blue: 0.23, alpha: 1), // yellow
    Stop(location: 1.00, red: 0.93, green: 0.55, blue: 0.23, alpha: 1), // orange
  ]

  /// The same run with both ends dissolving into the black, as on the mark.
  static var spectrumFaded: [Stop] {
    let inset: CGFloat = 0.11
    var stops = [Stop(location: 0, red: 0.30, green: 0.05, blue: 0.16, alpha: 0)]
    stops += spectrum.map {
      Stop(location: inset + $0.location * (1 - inset * 2), red: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
    }
    stops.append(Stop(location: 1, red: 0.40, green: 0.22, blue: 0.06, alpha: 0))
    return stops
  }

  static func cgGradient(_ stops: [Stop]) -> CGGradient? {
    let colors = stops.map { CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
    return CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
      colors: colors as CFArray,
      locations: stops.map(\.location)
    )
  }
}
