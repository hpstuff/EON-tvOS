import SwiftUI

/// Artwork view backed by `ImagePipeline`. Cached images appear instantly; fresh loads fade in.
struct RemoteImage<Placeholder: View>: View {
  let url: URL?
  var contentMode: ContentMode = .fill
  @ViewBuilder var placeholder: () -> Placeholder

  @State private var image: UIImage?
  @State private var loadedURL: URL?

  var body: some View {
    ZStack {
      if let image, loadedURL == url {
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

  private func load() async {
    guard let url else {
      image = nil
      loadedURL = nil
      return
    }
    if let hit = ImagePipeline.shared.cachedImage(for: url) {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        image = hit
        loadedURL = url
      }
      return
    }
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
