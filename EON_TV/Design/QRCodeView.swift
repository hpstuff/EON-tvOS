import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code for a link, drawn crisp at any size on a white tile with its quiet zone.
struct QRCodeView: View {
  let url: URL

  var body: some View {
    Group {
      if let image = Self.image(for: url) {
        Image(decorative: image, scale: 1)
          .interpolation(.none)
          .resizable()
          .aspectRatio(1, contentMode: .fit)
      } else {
        Color.clear
      }
    }
    .padding(14)
    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityLabel("QR code for the sign-in page")
  }

  private static func image(for url: URL) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(url.absoluteString.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    return CIContext().createCGImage(output, from: output.extent)
  }
}
