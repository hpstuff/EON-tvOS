import CoreGraphics
import Foundation
import ImageIO

// Renders the App Icon layers and Top Shelf images from the same geometry the app draws with.
//
//   swiftc -O Tools/BrandAssets/GenerateBrandAssets.swift EON_TV/Design/BrandGeometry.swift -o /tmp/genassets
//   /tmp/genassets "EON_TV/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
//
// The layered icon puts the black canvas at the back, the spectrum line in the middle and the
// letterforms in front, so the parallax on the Home screen moves the line through the letters.

enum Layer {
  case back, middle, front, flat
}

struct Job {
  let path: String
  let width: Int
  let height: Int
  let markWidth: CGFloat
  let layer: Layer
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: GenerateBrandAssets <brandassets directory>\n".utf8))
  exit(2)
}
let root = URL(fileURLWithPath: arguments[1])

func iconJobs(stack: String, width: Int, height: Int, scales: [Int]) -> [Job] {
  var jobs: [Job] = []
  for scale in scales {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    for (folder, layer) in [("Back", Layer.back), ("Middle", .middle), ("Front", .front)] {
      jobs.append(Job(
        path: "\(stack)/\(folder).imagestacklayer/Content.imageset/icon\(suffix).png",
        width: width * scale,
        height: height * scale,
        markWidth: CGFloat(width * scale) * 0.84,
        layer: layer
      ))
    }
  }
  return jobs
}

func shelfJobs(set: String, name: String, width: Int, height: Int) -> [Job] {
  [1, 2].map { scale in
    Job(
      path: "\(set)/\(name)\(scale == 1 ? "" : "@2x").png",
      width: width * scale,
      height: height * scale,
      markWidth: CGFloat(height * scale) * 1.15,
      layer: .flat
    )
  }
}

let jobs = iconJobs(stack: "App Icon.imagestack", width: 400, height: 240, scales: [1, 2])
  + iconJobs(stack: "App Icon - App Store.imagestack", width: 1280, height: 768, scales: [1])
  + shelfJobs(set: "Top Shelf Image.imageset", name: "topshelf", width: 1920, height: 720)
  + shelfJobs(set: "Top Shelf Image Wide.imageset", name: "topshelf-wide", width: 2320, height: 720)

func render(_ job: Job) throws {
  let size = CGSize(width: job.width, height: job.height)
  guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: nil,
          width: job.width,
          height: job.height,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
  else { throw NSError(domain: "GenerateBrandAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "no context"]) }

  // Draw in y-down coordinates, exactly as the app does.
  context.translateBy(x: 0, y: size.height)
  context.scaleBy(x: 1, y: -1)
  context.setShouldAntialias(true)
  context.setAllowsAntialiasing(true)

  if job.layer == .back || job.layer == .flat {
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
  }

  let unit = BrandGeometry.unitSize
  let cap = job.markWidth / unit.width
  let markSize = CGSize(width: unit.width * cap, height: unit.height * cap)
  let origin = CGPoint(x: (size.width - markSize.width) / 2, y: (size.height - markSize.height) / 2)

  if job.layer == .front || job.layer == .flat {
    context.saveGState()
    context.addRect(CGRect(origin: .zero, size: size))
    context.addRect(BrandGeometry.band(cap: cap, origin: origin))
    context.clip(using: .evenOdd)
    context.addPath(BrandGeometry.letters(cap: cap, origin: origin))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fillPath(using: .evenOdd)
    context.restoreGState()
  }

  if job.layer == .middle || job.layer == .flat {
    context.saveGState()
    let line = BrandGeometry.line(cap: cap, origin: origin)
    context.clip(to: line)
    if let gradient = BrandGeometry.cgGradient(BrandGeometry.spectrumFaded) {
      context.drawLinearGradient(
        gradient,
        start: CGPoint(x: line.minX, y: line.midY),
        end: CGPoint(x: line.maxX, y: line.midY),
        options: []
      )
    }
    context.restoreGState()
  }

  let url = root.appendingPathComponent(job.path)
  guard let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
  else { throw NSError(domain: "GenerateBrandAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"]) }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw NSError(domain: "GenerateBrandAssets", code: 3, userInfo: [NSLocalizedDescriptionKey: "finalize failed for \(url.path)"])
  }
  print("wrote \(job.path) \(job.width)x\(job.height)")
}

do {
  for job in jobs { try render(job) }
} catch {
  FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
  exit(1)
}
