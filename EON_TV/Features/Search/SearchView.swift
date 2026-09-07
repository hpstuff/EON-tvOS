import SwiftUI

/// Client-side search across the channel line-up and every loaded guide day. Results are
/// grouped by what the viewer can do with them: watch now, catch up, or look ahead.
struct SearchView: View {
  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock
  @Environment(FavoritesStore.self) private var favorites
  @Environment(PlaybackCoordinator.self) private var coordinator

  @State private var query = ""
  @FocusState private var focus: Focus?

  private enum Focus: Hashable {
    case channel(Int)
    case program(String, Int)
  }

  var body: some View {
    let results = store.search(query)
    ZStack {
      AmbientBackdrop(url: nil)
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: Theme.shelfSpacing) {
          if query.trimmingCharacters(in: .whitespaces).count < 2 {
            hint(
              symbol: "magnifyingglass",
              title: "Search EON TV",
              message: "Find channels by name, or programmes airing now, coming up, or available in catch-up."
            )
          } else if results.isEmpty {
            hint(
              symbol: "questionmark.circle",
              title: "No matches for “\(query)”",
              message: "Try a shorter word, or a channel name."
            )
          } else {
            if !results.channels.isEmpty {
              Shelf(title: "Channels", items: results.channels) { channel in
                Button {
                  coordinator.playLive(channel, lineup: store.channels)
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
                .onPlayPauseCommand { coordinator.playLive(channel, lineup: store.channels) }
              }
            }
            if !results.onNow.isEmpty {
              shelf("On Now", key: "now", items: results.onNow)
            }
            if !results.catchUp.isEmpty {
              shelf("Catch Up", key: "catchup", items: results.catchUp)
            }
            if !results.upcoming.isEmpty {
              shelf("Coming Up", key: "upcoming", items: results.upcoming)
            }
          }
        }
        .padding(.top, 48)
        .padding(.bottom, 90)
      }
      .scrollClipDisabled()
    }
    .searchable(text: $query, prompt: "Channels and programmes")
    .onChange(of: clock.nowMs) { _, _ in store.recomputeShelves() }
  }

  private func shelf(_ title: String, key: String, items: [ContentStore.ProgramItem]) -> some View {
    Shelf(title: title, items: items) { item in
      Button {
        coordinator.open(item, nowMs: clock.nowMs, lineup: store.channels)
      } label: {
        ProgramCard(channel: item.channel, schedule: item.schedule, width: 360)
      }
      .buttonStyle(.bare)
      .focused($focus, equals: .program(key, item.id))
      .onPlayPauseCommand { coordinator.open(item, nowMs: clock.nowMs, lineup: store.channels) }
      .contextMenu { ProgramContextMenu(item: item, lineup: store.channels) }
    }
  }

  private func hint(symbol: String, title: String, message: String) -> some View {
    VStack(spacing: 18) {
      Image(systemName: symbol)
        .font(.system(size: 60, weight: .light))
        .foregroundStyle(Theme.textTertiary)
      Text(title)
        .font(.system(size: 34, weight: .regular))
        .foregroundStyle(Theme.textPrimary)
      Text(message)
        .font(.system(size: 25))
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 820)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 60)
  }
}
