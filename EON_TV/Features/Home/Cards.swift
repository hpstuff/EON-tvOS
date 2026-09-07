import SwiftUI

/// Programme + channel card used on every shelf. The artwork carries the channel logo, the
/// live badge or start time and airing progress; the text below brightens with focus. The card
/// is the label of a `.bare` button so only the artwork lifts, never the caption.
struct ProgramCard: View {
  let channel: Channel
  let schedule: Schedule?
  var width: CGFloat = Theme.programCardWidth
  var resumeFraction: Double? = nil
  var showsChannelName = true

  @Environment(LiveClock.self) private var clock
  @Environment(\.isFocused) private var isFocused

  private var height: CGFloat { width * 9 / 16 }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      artwork
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(isFocused ? 0.9 : 0.08), lineWidth: isFocused ? 4 : 1)
        }
        .scaleEffect(isFocused ? 1.07 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.6 : 0.25), radius: isFocused ? 34 : 14, y: isFocused ? 22 : 8)
        .shadow(color: Theme.glow.opacity(isFocused ? 0.3 : 0), radius: 40)
        .zIndex(isFocused ? 1 : 0)
        .animation(Theme.focusAnimation, value: isFocused)

      caption
        .padding(.horizontal, 6)
        .offset(y: isFocused ? 10 : 0)
        .animation(Theme.focusAnimation, value: isFocused)
    }
    .frame(width: width)
  }

  private var artwork: some View {
    let now = clock.nowMs
    return ZStack {
      RemoteImage(url: schedule?.posterURL) {
        ZStack {
          ArtworkPlaceholder(seed: channel.id)
          ChannelLogo(channel: channel, height: 64, platter: false)
        }
      }
      .frame(width: width, height: height)

      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.55), location: 0),
          .init(color: .clear, location: 0.35),
          .init(color: .clear, location: 0.6),
          .init(color: .black.opacity(0.7), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      VStack {
        HStack(alignment: .top) {
          ChannelLogo(channel: channel, height: 30)
          Spacer()
          statusBadge(now: now)
        }
        Spacer()
        if let resumeFraction {
          ProgressBar(progress: resumeFraction, height: 7)
        } else if let schedule, schedule.isAiring(at: now) {
          ProgressBar(progress: schedule.progress(at: now), height: 7)
        }
      }
      .padding(16)
    }
  }

  @ViewBuilder
  private func statusBadge(now: Int) -> some View {
    if resumeFraction != nil {
      Tag(text: "RESUME", solid: true)
    } else if let schedule {
      if schedule.isAiring(at: now) {
        LiveBadge(compact: true)
      } else if schedule.isUpcoming(at: now) {
        Tag(text: schedule.startDate.shortTime)
      } else if channel.isWithinCatchUpWindow(schedule, nowMs: now) {
        Tag(text: "CATCH UP")
      }
    }
  }

  private var caption: some View {
    VStack(alignment: .leading, spacing: 5) {
      if let schedule {
        Text(schedule.title)
          .font(.cardTitle)
          .foregroundStyle(isFocused ? Theme.textPrimary : Theme.textPrimary.opacity(0.88))
          .lineLimit(1)
        Text(metaLine(for: schedule))
          .font(.cardMeta)
          .foregroundStyle(Theme.textSecondary)
          .lineLimit(1)
      } else {
        Text(channel.name)
          .font(.cardTitle)
          .foregroundStyle(Theme.textPrimary.opacity(0.88))
          .lineLimit(1)
        SkeletonBlock(cornerRadius: 6)
          .frame(width: width * 0.55, height: 20)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func metaLine(for schedule: Schedule) -> String {
    let now = clock.nowMs
    var parts: [String] = []
    if showsChannelName { parts.append(channel.name) }
    if schedule.isAiring(at: now) {
      parts.append("\(schedule.remainingMinutes(at: now)) min left")
    } else if schedule.isUpcoming(at: now) {
      let minutes = schedule.minutesUntilStart(at: now)
      parts.append(minutes < 60 ? "Starts in \(minutes) min" : schedule.timeRangeText)
    } else {
      parts.append(schedule.timeRangeText)
    }
    return parts.joined(separator: " · ")
  }
}

/// Compact channel tile: the logo on glass with what's airing underneath.
struct ChannelTile: View {
  let channel: Channel
  let number: Int
  let schedule: Schedule?
  var isFavorite = false
  var width: CGFloat = Theme.channelTileWidth

  @Environment(LiveClock.self) private var clock
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
          .fill(isFocused ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(AuroraGeometry.palette(seed: channel.id).tileTint))
        ChannelLogo(channel: channel, height: 72, platter: false)
          .padding(.horizontal, 28)
        VStack {
          HStack {
            Text(String(number))
              .font(.channelNumber)
              .foregroundStyle(Theme.textTertiary)
            Spacer()
            if isFavorite {
              Image(systemName: "heart.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            }
          }
          Spacer()
          if let schedule, schedule.isAiring(at: clock.nowMs) {
            ProgressBar(progress: schedule.progress(at: clock.nowMs), track: .white.opacity(0.12), height: 5)
          }
        }
        .padding(14)
      }
      .frame(width: width, height: width * 9 / 16)
      .overlay {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
          .strokeBorder(isFocused ? Color.white.opacity(0.9) : Theme.stroke, lineWidth: isFocused ? 4 : 1)
      }
      .scaleEffect(isFocused ? 1.08 : 1)
      .shadow(color: .black.opacity(isFocused ? 0.55 : 0.2), radius: isFocused ? 30 : 10, y: isFocused ? 18 : 6)
      .shadow(color: Theme.glow.opacity(isFocused ? 0.3 : 0), radius: 36)
      .zIndex(isFocused ? 1 : 0)

      VStack(alignment: .leading, spacing: 4) {
        Text(channel.name)
          .font(.system(size: 24, weight: .medium))
          .foregroundStyle(Theme.textPrimary.opacity(isFocused ? 1 : 0.88))
          .lineLimit(1)
        if let schedule {
          Text(schedule.title)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
        } else {
          SkeletonBlock(cornerRadius: 5).frame(width: width * 0.6, height: 18)
        }
      }
      .padding(.horizontal, 4)
      .offset(y: isFocused ? 8 : 0)
    }
    .frame(width: width)
    .animation(Theme.focusAnimation, value: isFocused)
  }
}

/// Horizontal shelf of cards. Each shelf is its own focus section so vertical moves land on
/// the nearest card in the next shelf, and horizontal moves never jump rows. A shelf can open
/// scrolled to a particular item (e.g. the programme a details screen is about).
struct Shelf<Item: Identifiable, Content: View>: View {
  let title: String
  var subtitle: String? = nil
  let items: [Item]
  var initialItemID: Item.ID? = nil
  @ViewBuilder let content: (Item) -> Content

  @State private var scrolledID: Item.ID?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(title: title, subtitle: subtitle)
        .padding(.horizontal, Theme.screenMargin)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: Theme.cardSpacing) {
          ForEach(items) { item in
            content(item)
          }
        }
        .scrollTargetLayout()
        .padding(.top, 24)
        .padding(.bottom, 34)
      }
      .contentMargins(.horizontal, Theme.screenMargin, for: .scrollContent)
      .scrollPosition(id: $scrolledID, anchor: .leading)
      .scrollClipDisabled()
      .onAppear {
        if let initialItemID { scrolledID = initialItemID }
      }
    }
    .focusSection()
  }
}

/// Long-press menu shared by programme cards everywhere.
struct ProgramContextMenu: View {
  let item: ContentStore.ProgramItem
  let lineup: [Channel]

  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock
  @Environment(FavoritesStore.self) private var favorites
  @Environment(PlaybackCoordinator.self) private var coordinator

  var body: some View {
    let now = clock.nowMs
    let channel = item.channel
    let schedule = item.schedule

    Button { coordinator.playLive(channel, lineup: lineup) } label: {
      Label("Watch \(channel.name) Live", systemImage: "play.fill")
    }
    if schedule.isAiring(at: now), channel.canStartOver {
      Button { coordinator.startOver(schedule, on: channel, lineup: lineup) } label: {
        Label("Start Over", systemImage: "backward.end.fill")
      }
    }
    if schedule.hasEnded(at: now), channel.isWithinCatchUpWindow(schedule, nowMs: now) {
      Button { coordinator.catchUp(schedule, on: channel, lineup: lineup) } label: {
        Label("Play from Start", systemImage: "gobackward")
      }
    }
    Button { coordinator.showDetails(item) } label: {
      Label("Details", systemImage: "info.circle")
    }
    Button { coordinator.openGuide(for: channel) } label: {
      Label("Open in Guide", systemImage: "list.bullet.rectangle")
    }
    Button { favorites.toggle(channel) } label: {
      Label(
        favorites.contains(channel.id) ? "Remove from Favorites" : "Add to Favorites",
        systemImage: favorites.contains(channel.id) ? "heart.slash" : "heart"
      )
    }
  }
}
