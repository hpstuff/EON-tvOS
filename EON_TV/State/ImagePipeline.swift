import UIKit
import ImageIO

enum ImageError: Error {
  case badStatus(Int)
  case undecodable
}

/// Memory + disk cached image loading with request coalescing and off-main decoding.
///
/// The platform's artwork is modest (XL renditions are 480×270), so the pipeline is tuned for
/// many small images scrolling quickly: a generous memory cache keyed by URL, a dedicated disk
/// cache, and one network request per URL no matter how many cards ask for it.
actor ImagePipeline {
  static let shared = ImagePipeline()

  nonisolated(unsafe) private let memory: NSCache<NSURL, UIImage> = {
    let cache = NSCache<NSURL, UIImage>()
    cache.totalCostLimit = 200 * 1024 * 1024
    cache.countLimit = 3_000
    return cache
  }()

  private var inFlight: [URL: Task<UIImage, Error>] = [:]
  private let session: URLSession

  init() {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(
      memoryCapacity: 32 * 1024 * 1024,
      diskCapacity: 300 * 1024 * 1024,
      diskPath: "eon-artwork"
    )
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    configuration.httpMaximumConnectionsPerHost = 6
    configuration.timeoutIntervalForRequest = 20
    session = URLSession(configuration: configuration)
  }

  /// Synchronous memory-cache lookup so already-seen artwork renders without a flash.
  nonisolated func cachedImage(for url: URL) -> UIImage? {
    memory.object(forKey: url as NSURL)
  }

  func image(for url: URL) async throws -> UIImage {
    if let hit = memory.object(forKey: url as NSURL) { return hit }
    if let running = inFlight[url] { return try await running.value }

    let session = self.session
    let task = Task.detached(priority: .userInitiated) { () throws -> UIImage in
      #if DEBUG
      if url.scheme == "demo" || url.host()?.hasSuffix("demo.local") == true { return DemoArtwork.render(url) }
      #endif
      let (data, response) = try await session.data(from: url)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw ImageError.badStatus(http.statusCode)
      }
      guard let image = ImagePipeline.decode(data) else { throw ImageError.undecodable }
      return image
    }
    inFlight[url] = task
    defer { inFlight[url] = nil }

    let image = try await task.value
    memory.setObject(image, forKey: url as NSURL, cost: image.byteCost)
    return image
  }

  /// Forces decoding off the main thread so first paint of a card never stutters.
  nonisolated static func decode(_ data: Data) -> UIImage? {
    let options: [CFString: Any] = [
      kCGImageSourceShouldCache: true,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    else { return UIImage(data: data) }
    return UIImage(cgImage: cgImage)
  }
}

private extension UIImage {
  nonisolated var byteCost: Int {
    Int(size.width * scale * size.height * scale * 4)
  }
}
