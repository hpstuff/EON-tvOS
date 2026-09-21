import SwiftUI

/// Artwork view backed by `ImagePipeline`. Cached images appear instantly; fresh loads fade in.
///
/// The memory cache is consulted synchronously while the body is built, so a card scrolling
/// into view with artwork the app has already seen paints that artwork on its very first frame.
/// Going through the loading task for cache hits would show the placeholder for a frame first,
/// which reads as a flicker across a shelf while focus moves quickly.
struct RemoteImage<Placeholder: View>: View {
  let url: URL?
  var contentMode: ContentMode = .fill
  @ViewBuilder var placeholder: () -> Placeholder

  @State private var image: UIImage?
  @State private var loadedURL: URL?

  var body: some View {
    ZStack {
      if let image = resolvedImage {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
          .transition(.opacity)
      } else {
        placeholder()
      }
    }
    .task(id: url) { await load() }
  }

  /// The image fetched for this URL, or whatever the memory cache already holds for it.
  private var resolvedImage: UIImage? {
    guard let url else { return nil }
    if let image, loadedURL == url { return image }
    return ImagePipeline.shared.cachedImage(for: url)
  }

  private func load() async {
    guard let url else {
      image = nil
      loadedURL = nil
      return
    }
    guard ImagePipeline.shared.cachedImage(for: url) == nil else { return }
    do {
      let loaded = try await ImagePipeline.shared.image(for: url)
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.25)) {
        image = loaded
        loadedURL = url
      }
    } catch {
      // Keep the placeholder; artwork is decorative and must never block the UI.
    }
  }
}

extension RemoteImage where Placeholder == ArtworkPlaceholder {
  init(url: URL?, contentMode: ContentMode = .fill) {
    self.init(url: url, contentMode: contentMode) { ArtworkPlaceholder() }
  }
}

/// Shown before artwork arrives or when a programme has none: a still of the aurora, varied by
/// `seed` so neighbouring cards never look identical.
struct ArtworkPlaceholder: View {
  var seed: Int = 0

  var body: some View {
    ZStack {
      Color(red: 0.02, green: 0.02, blue: 0.05)
      AuroraWaves(seed: seed, intensity: 0.95, blurFraction: 0.07)
    }
  }
}
