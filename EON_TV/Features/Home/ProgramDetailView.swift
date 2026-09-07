import SwiftUI

/// Full-screen programme details with the channel's schedule for that day underneath, so a
/// viewer can move straight from "what is this?" to "what else is on here?".
struct ProgramDetailView: View {
  let item: ContentStore.ProgramItem

  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock
  @Environment(FavoritesStore.self) private var favorites
  @Environment(PlaybackCoordinator.self) private var coordinator
  @Environment(\.dismiss) private var dismiss

  @FocusState private var focus: Focus?

  private enum Focus: Hashable {
    case primary, secondary, favorite, guide
    case program(Int)
  }

  private var channel: Channel { item.channel }
  private var schedule: Schedule { item.schedule }

  var body: some View {
    let now = clock.nowMs
    ZStack {
      AmbientBackdrop(url: schedule.posterURL ?? channel.logoURL, intensity: 0.7)

      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 40) {
          HStack(alignment: .top, spacing: 56) {
            RemoteImage(url: schedule.posterURL) {
              ZStack {
                ArtworkPlaceholder(seed: channel.id)
                ChannelLogo(channel: channel, height: 100, platter: false)
              }
            }
            .frame(width: 720, height: 405)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.6), radius: 40, y: 24)
            .shadow(color: Theme.glow.opacity(0.18), radius: 70)

            VStack(alignment: .leading, spacing: 20) {
              HStack(spacing: 14) {
                ChannelLogo(channel: channel, height: 40, platter: false)
                Text(channel.name)
                  .font(.heroMeta)
                  .foregroundStyle(Theme.textSecondary)
                Text("· Channel \(store.channelNumber(channel))")
                  .font(.heroMeta)
                  .foregroundStyle(Theme.textTertiary)
              }
              Text(schedule.title)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
              if let subtitle = schedule.subtitleText {
                Text(subtitle)
                  .font(.heroMeta)
                  .foregroundStyle(Theme.textSecondary)
              }
              HStack(spacing: 16) {
                statusTag(now: now)
                Text("\(schedule.startDate.relativeDayLabel()) · \(schedule.timeRangeText) · \(schedule.durationMinutes) min")
                  .font(.heroMeta)
                  .foregroundStyle(Theme.textSecondary)
              }
              if schedule.isAiring(at: now) {
                ProgressBar(progress: schedule.progress(at: now))
                  .frame(width: 520)
              }
              Text(schedule.descriptionText ?? "No description available for this programme.")
                .font(.heroBody)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(6)

              actions(now: now)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.horizontal, Theme.screenMargin)
          .padding(.top, 60)
          .focusSection()

          daySchedule(now: now)
        }
        .padding(.bottom, 80)
      }
      .scrollClipDisabled()
    }
    .defaultFocus($focus, .primary)
    .onExitCommand { dismiss() }
  }

  @ViewBuilder
  private func statusTag(now: Int) -> some View {
    if schedule.isAiring(at: now) {
      LiveBadge()
    } else if schedule.isUpcoming(at: now) {
      let minutes = schedule.minutesUntilStart(at: now)
      Tag(text: minutes < 60 ? "STARTS IN \(minutes) MIN" : "UPCOMING")
    } else if channel.isWithinCatchUpWindow(schedule, nowMs: now) {
      Tag(text: "AVAILABLE IN CATCH UP")
    } else {
      Tag(text: "ENDED")
    }
  }

  @ViewBuilder
  private func actions(now: Int) -> some View {
    let lineup = store.channels
    HStack(spacing: 18) {
      if schedule.isAiring(at: now) {
        Button { coordinator.playLive(channel, lineup: lineup); dismiss() } label: {
          Label("Watch Live", systemImage: "play.fill")
        }
        .buttonStyle(.prominentPill)
        .focused($focus, equals: .primary)
        if channel.canStartOver {
          Button { coordinator.startOver(schedule, on: channel, lineup: lineup); dismiss() } label: {
            Label("Start Over", systemImage: "backward.end.fill")
          }
          .buttonStyle(.pill)
          .focused($focus, equals: .secondary)
        }
      } else if schedule.hasEnded(at: now), channel.isWithinCatchUpWindow(schedule, nowMs: now) {
        Button { coordinator.catchUp(schedule, on: channel, lineup: lineup); dismiss() } label: {
          Label("Play from Start", systemImage: "gobackward")
        }
        .buttonStyle(.prominentPill)
        .focused($focus, equals: .primary)
        Button { coordinator.playLive(channel, lineup: lineup); dismiss() } label: {
          Label("Watch Live", systemImage: "play.fill")
        }
        .buttonStyle(.pill)
        .focused($focus, equals: .secondary)
      } else {
        Button { coordinator.playLive(channel, lineup: lineup); dismiss() } label: {
          Label("Watch \(channel.name) Live", systemImage: "play.fill")
        }
        .buttonStyle(.prominentPill)
        .focused($focus, equals: .primary)
      }

      Button { favorites.toggle(channel) } label: {
        Label(
          favorites.contains(channel.id) ? "Favorite" : "Add Favorite",
          systemImage: favorites.contains(channel.id) ? "heart.fill" : "heart"
        )
      }
      .buttonStyle(.pill)
      .focused($focus, equals: .favorite)

      Button { coordinator.openGuide(for: channel); dismiss() } label: {
        Label("Guide", systemImage: "list.bullet.rectangle")
      }
      .buttonStyle(.pill)
      .focused($focus, equals: .guide)
    }
  }

  @ViewBuilder
  private func daySchedule(now: Int) -> some View {
    let day = schedule.startDate.startOfTheDay
    let programmes = store.schedules(for: channel.id, day: day) ?? []
    let items = programmes.map { ContentStore.ProgramItem(channel: channel, schedule: $0) }

    if !items.isEmpty {
      Shelf(title: "\(schedule.startDate.relativeDayLabel()) on \(channel.name)", items: items, initialItemID: schedule.id) { entry in
        Button {
          if entry.schedule.id == schedule.id { return }
          coordinator.detail = entry
        } label: {
          ProgramCard(channel: channel, schedule: entry.schedule, width: 340, showsChannelName: false)
        }
        .buttonStyle(.bare)
        .focused($focus, equals: .program(entry.schedule.id))
        .contextMenu { ProgramContextMenu(item: entry, lineup: store.channels) }
      }
    }
  }
}
