import SwiftUI

/// The EON mark: white letterforms sliced by the spectrum line. `lineProgress` reveals the line
/// from the left, which lets the launch screen draw it in.
struct BrandMark: View {
  var height: CGFloat = 96
  var lineProgress: CGFloat = 1

  var body: some View {
    let cap = BrandGeometry.cap(forHeight: height)
    let size = BrandGeometry.size(forHeight: height)
    let band = BrandGeometry.band(cap: cap)
    let line = BrandGeometry.line(cap: cap)

    ZStack(alignment: .topLeading) {
      Canvas { context, _ in
        var keep = Path(CGRect(origin: .zero, size: size))
        keep.addRect(band)
        context.clip(to: keep, style: FillStyle(eoFill: true))
        context.fill(
          Path(BrandGeometry.letters(cap: cap)),
          with: .color(.white),
          style: FillStyle(eoFill: true)
        )
      }

      Rectangle()
        .fill(Theme.spectrumFaded)
        .frame(width: line.width, height: line.height)
        .mask(alignment: .leading) {
          Rectangle().frame(width: max(0, line.width * lineProgress))
        }
        .offset(y: line.minY)
    }
    .frame(width: size.width, height: size.height)
    .accessibilityLabel("EON")
  }
}

/// A thin run of the spectrum. Decorative rules fade at both ends like the mark; functional
/// bars use the full run.
struct SpectrumLine: View {
  var faded = true
  var height: CGFloat = 2

  var body: some View {
    Rectangle()
      .fill(faded ? Theme.spectrumFaded : Theme.spectrum)
      .frame(height: height)
  }
}

/// Indeterminate progress in the brand's own language: a short piece of the spectrum travelling
/// along a dim track.
struct SpectrumLoadingLine: View {
  var height: CGFloat = 3

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 60)) { context in
      let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
      GeometryReader { proxy in
        let width = proxy.size.width
        let segment = width * 0.38
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.10))
          Capsule()
            .fill(Theme.spectrum)
            .frame(width: segment)
            .offset(x: -segment + (width + segment) * phase)
        }
        .clipShape(Capsule())
      }
    }
    .frame(height: height)
    .accessibilityLabel("Loading")
  }
}
