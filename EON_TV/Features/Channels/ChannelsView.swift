import SwiftUI

/// Channel browsing: a filter rail (all, favourites, categories) over a tile grid. Filters
/// apply on click, so directional moves through the rail never change the grid unexpectedly.
/// The grid drops columns as the viewer's text size grows so tiles keep room for their captions.
struct ChannelsView: View {
  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock
  @Environment(FavoritesStore.self) private var favorites
  @Environment(PlaybackCoordinator.self) private var coordinator
  @ScaledMetric(relativeTo: .caption) private var textScale: CGFloat = 1

  @State private var filter: Filter = .all
  @FocusState private var focus: Focus?

  enum Filter: Hashable {
    case all, favorites
    case category(Int)
  }

  private enum Focus: Hashable {
    case filter(Filter)
    case channel(Int)
  }

  private static let columnSpacing: CGFloat = 34

  /// Tile width follows the caption size; the column count is whatever fits inside the margins.
  private var tileWidth: CGFloat { Theme.channelTileWidth * min(textScale, Theme.maxArtworkScale) }

  private var columns: [GridItem] {
    let available = 1920 - Theme.screenMargin * 2 + Self.columnSpacing
    let count = max(2, Int(available / (tileWidth + Self.columnSpacing)))
    return Array(repeating: GridItem(.fixed(tileWidth), spacing: Self.columnSpacing), count: count)
  }

  var body: some View {
    ZStack {
      AmbientBackdrop(url: nil)
      if store.hasChannels {
        content
      } else if case .failed(let message) = store.channelsState {
        StatusView(symbol: "tv.slash", title: "Couldn't load your channels", message: message, actionTitle: "Try Again") {
          Task { await store.loadInitial() }
        }
      } else {
        ProgressView().tint(Theme.textSecondary)
      }
    }
    .onChange(of: clock.nowMs) { _, _ in store.recomputeShelves() }
  }

  private var visibleChannels: [Channel] {
    switch filter {
    case .all: return store.channels
    case .favorites: return favorites.channels(in: store)
    case .category(let id): return store.categories.first { $0.id == id }?.channels ?? []
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 28) {
      HStack(alignment: .firstTextBaseline, spacing: 20) {
        Text("Channels")
          .font(.screenTitle)
          .foregroundStyle(Theme.textPrimary)
        Text("\(visibleChannels.count)")
          .font(.headline.weight(.regular))
          .foregroundStyle(Theme.textTertiary)
          .contentTransition(.numericText())
        Spacer()
      }
      .padding(.horizontal, Theme.screenMargin)
      .padding(.top, Theme.contentTop)

      filterRail

      ScrollView(.vertical) {
        if visibleChannels.isEmpty {
          emptyState
        } else {
          LazyVGrid(columns: columns, alignment: .leading, spacing: 44) {
            ForEach(visibleChannels) { channel in
              tile(for: channel)
            }
          }
          .padding(.horizontal, Theme.screenMargin)
          .padding(.top, 30)
          .padding(.bottom, 90)
        }
      }
      .scrollClipDisabled()
      .focusSection()
    }
    .defaultFocus($focus, .filter(.all))
  }

  private var filterRail: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 16) {
        chip("All", filter: .all)
        chip("Favorites", filter: .favorites, symbol: "heart.fill")
        ForEach(store.browsableCategories) { category in
          chip(category.name, filter: .category(category.id))
        }
      }
      .padding(.horizontal, Theme.screenMargin)
      .padding(.vertical, 16)
    }
    .scrollClipDisabled()
    .focusSection()
  }

  private func chip(_ title: String, filter value: Filter, symbol: String? = nil) -> some View {
    Button {
      withAnimation(Theme.crossfade) { filter = value }
    } label: {
      FilterChipLabel(title: title, symbol: symbol, isSelected: filter == value)
    }
    .buttonStyle(.glass)
    .focused($focus, equals: .filter(value))
  }

  private func tile(for channel: Channel) -> some View {
    Button {
      coordinator.playLive(channel, lineup: visibleChannels)
    } label: {
      ChannelTile(
        channel: channel,
        number: store.channelNumber(channel),
        schedule: store.nowPlaying(channel),
        isFavorite: favorites.contains(channel.id)
      )
    }
    .buttonStyle(.bare)
    .focused($focus, equals: .channel(channel.id))
    .onPlayPauseCommand { coordinator.playLive(channel, lineup: visibleChannels) }
    .contextMenu {
      if let schedule = store.nowPlaying(channel) {
        ProgramContextMenu(item: .init(channel: channel, schedule: schedule), lineup: visibleChannels)
      } else {
        Button { coordinator.playLive(channel, lineup: visibleChannels) } label: {
          Label("Watch Live", systemImage: "play.fill")
        }
        Button { favorites.toggle(channel) } label: {
          Label(favorites.contains(channel.id) ? "Remove from Favorites" : "Add to Favorites", systemImage: "heart")
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 18) {
      Image(systemName: filter == .favorites ? "heart" : "tv")
        .font(.title.weight(.light))
        .foregroundStyle(Theme.textTertiary)
      Text(filter == .favorites ? "No favorites yet" : "No channels here")
        .font(.headline.weight(.regular))
        .foregroundStyle(Theme.textPrimary)
      Text(filter == .favorites
           ? "Hold the touch surface on any channel and choose “Add to Favorites”."
           : "Nothing in this category is part of your subscription.")
        .font(.body.weight(.regular))
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 900)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 120)
  }
}
