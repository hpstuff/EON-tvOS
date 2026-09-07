import SwiftUI

/// Channel browsing: a filter rail (all, favourites, categories) over a tile grid. Filters
/// apply on click, so directional moves through the rail never change the grid unexpectedly.
struct ChannelsView: View {
  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock
  @Environment(FavoritesStore.self) private var favorites
  @Environment(PlaybackCoordinator.self) private var coordinator

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

  private let columns = Array(repeating: GridItem(.fixed(Theme.channelTileWidth), spacing: 34), count: 5)

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
          .font(.system(size: 30, weight: .light))
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
    .buttonStyle(.bare)
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
        .font(.system(size: 64, weight: .light))
        .foregroundStyle(Theme.textTertiary)
      Text(filter == .favorites ? "No favorites yet" : "No channels here")
        .font(.system(size: 34, weight: .regular))
        .foregroundStyle(Theme.textPrimary)
      Text(filter == .favorites
           ? "Hold the touch surface on any channel and choose “Add to Favorites”."
           : "Nothing in this category is part of your subscription.")
        .font(.system(size: 25))
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 120)
  }
}

/// Filter chip that shows selection with an accent outline and focus with a white platter.
struct FilterChipLabel: View {
  let title: String
  var symbol: String? = nil
  let isSelected: Bool
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    HStack(spacing: 10) {
      if let symbol {
        Image(systemName: symbol)
          .font(.system(size: 20, weight: .semibold))
      }
      Text(title)
        .font(.system(size: 24, weight: .medium))
    }
    .foregroundStyle(isFocused ? Theme.textOnFocus : (isSelected ? Theme.textPrimary : Theme.textSecondary))
    .padding(.horizontal, 26)
    .padding(.vertical, 13)
    .background {
      Capsule().fill(isFocused ? Color.white : (isSelected ? Theme.surfaceStrong : Theme.surface))
    }
    .overlay {
      Capsule().strokeBorder(isFocused ? Color.clear : (isSelected ? Theme.strokeStrong : Theme.stroke), lineWidth: 1.5)
    }
    .scaleEffect(isFocused ? 1.06 : 1)
    .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 18, y: 10)
    .animation(Theme.focusAnimation, value: isFocused)
    .animation(Theme.focusAnimation, value: isSelected)
  }
}
