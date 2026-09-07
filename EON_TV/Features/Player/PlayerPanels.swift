import SwiftUI

/// Bottom sheet shared by the player panels: a dimmed backdrop, a title row and content.
private struct PlayerSheet<Content: View>: View {
  let title: String
  let subtitle: String?
  let onClose: () -> Void
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack {
      Spacer()
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
          Text(title)
            .font(.system(size: 34, weight: .regular))
            .foregroundStyle(.white)
          if let subtitle {
            Text(subtitle)
              .font(.system(size: 24, weight: .medium))
              .foregroundStyle(.white.opacity(0.6))
          }
          Spacer()
          Text("Press Back to close")
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, Theme.screenMargin)
        content()
      }
      .padding(.top, 34)
      .padding(.bottom, 44)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: .black.opacity(0.7), location: 0.12),
            .init(color: .black.opacity(0.92), location: 1),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        .padding(.top, -120)
        .ignoresSafeArea()
      }
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }
}

/// Focus can only land on a panel item once it exists in the hierarchy, so panels assign it a
/// beat after appearing and fall back to the first item if the preferred one isn't built yet.
private func focusPanelItem(_ focus: FocusState<PlayerScreenContent.PlayerFocus?>.Binding, preferred: String, fallback: String?) {
  Task {
    try? await Task.sleep(for: .milliseconds(80))
    focus.wrappedValue = .panelItem(preferred)
    try? await Task.sleep(for: .milliseconds(120))
    if focus.wrappedValue == nil, let fallback {
      focus.wrappedValue = .panelItem(fallback)
    }
  }
}

/// Today's programmes on the current channel. Past ones play from the start, the current one
/// restarts, upcoming ones are shown but not playable.
struct SchedulePanel: View {
  let controller: PlayerController
  var focus: FocusState<PlayerScreenContent.PlayerFocus?>.Binding
  let onClose: () -> Void

  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock

  var body: some View {
    let now = clock.nowMs
    let channel = controller.channel
    let programmes = store.schedules(for: channel.id, day: clock.dayStart) ?? []
    let current = controller.currentProgram ?? programmes.first { $0.isAiring(at: now) }

    PlayerSheet(title: channel.name, subtitle: "Today", onClose: onClose) {
      if programmes.isEmpty {
        Text("The guide for this channel hasn't loaded yet.")
          .font(.system(size: 24))
          .foregroundStyle(Theme.textTertiary)
          .padding(.horizontal, Theme.screenMargin)
          .frame(height: 300)
      } else {
        ScrollViewReader { proxy in
          ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 24) {
              ForEach(programmes) { schedule in
                let playable = schedule.isAiring(at: now) || channel.isWithinCatchUpWindow(schedule, nowMs: now)
                Button {
                  guard playable else { return }
                  controller.play(schedule)
                  onClose()
                } label: {
                  ProgramCard(channel: channel, schedule: schedule, width: 320, showsChannelName: false)
                    .opacity(playable ? 1 : 0.45)
                }
                .buttonStyle(.bare)
                .focused(focus, equals: .panelItem("schedule-\(schedule.id)"))
                .id(schedule.id)
              }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, 20)
            .padding(.bottom, 30)
          }
          .frame(height: 330)
          .scrollClipDisabled()
          .onAppear {
            if let current {
              proxy.scrollTo(current.id, anchor: .leading)
            }
            let preferred = current ?? programmes.first
            if let preferred {
              focusPanelItem(focus, preferred: "schedule-\(preferred.id)", fallback: programmes.first.map { "schedule-\($0.id)" })
            }
          }
        }
        .focusSection()
      }
    }
  }
}

/// The surrounding line-up with what's on now; selecting a tile switches channel.
struct ChannelsPanel: View {
  let controller: PlayerController
  var focus: FocusState<PlayerScreenContent.PlayerFocus?>.Binding
  let onClose: () -> Void

  @Environment(ContentStore.self) private var store
  @Environment(FavoritesStore.self) private var favorites

  var body: some View {
    PlayerSheet(title: "Channels", subtitle: "\(controller.lineup.count) in this list", onClose: onClose) {
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: 26) {
            ForEach(controller.lineup) { channel in
              Button {
                controller.switchChannel(channel)
                onClose()
              } label: {
                ChannelTile(
                  channel: channel,
                  number: store.channelNumber(channel),
                  schedule: store.nowPlaying(channel),
                  isFavorite: favorites.contains(channel.id),
                  width: 260
                )
              }
              .buttonStyle(.bare)
              .focused(focus, equals: .panelItem("channel-\(channel.id)"))
              .id(channel.id)
            }
          }
          .padding(.horizontal, Theme.screenMargin)
          .padding(.top, 20)
          .padding(.bottom, 30)
        }
        .frame(height: 290)
        .scrollClipDisabled()
        .onAppear {
          proxy.scrollTo(controller.channel.id, anchor: .center)
          focusPanelItem(focus, preferred: "channel-\(controller.channel.id)", fallback: controller.lineup.first.map { "channel-\($0.id)" })
        }
      }
      .focusSection()
    }
  }
}

/// Subtitle and audio track selection for the current stream.
struct MediaOptionsPanel: View {
  let controller: PlayerController
  var focus: FocusState<PlayerScreenContent.PlayerFocus?>.Binding
  let onClose: () -> Void

  var body: some View {
    PlayerSheet(title: "Audio & Subtitles", subtitle: nil, onClose: onClose) {
      HStack(alignment: .top, spacing: 80) {
        if !controller.hasMediaOptions {
          Button {
            onClose()
          } label: {
            Label("This stream has no alternative audio or subtitle tracks", systemImage: "captions.bubble")
          }
          .buttonStyle(.pill)
          .focused(focus, equals: .panelItem("option-none"))
        }
        if !controller.subtitleOptions.isEmpty {
          optionColumn(title: "Subtitles", options: controller.subtitleOptions)
        }
        if !controller.audioOptions.isEmpty {
          optionColumn(title: "Audio", options: controller.audioOptions)
        }
        Spacer()
      }
      .padding(.horizontal, Theme.screenMargin)
      .padding(.top, 10)
      .padding(.bottom, 20)
      .onAppear {
        if let first = controller.subtitleOptions.first ?? controller.audioOptions.first {
          focusPanelItem(focus, preferred: "option-\(first.id)", fallback: nil)
        } else {
          focusPanelItem(focus, preferred: "option-none", fallback: nil)
        }
      }
    }
  }

  private func optionColumn(title: String, options: [PlayerController.MediaOption]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title.uppercased())
        .font(.system(size: 20, weight: .semibold))
        .kerning(1)
        .foregroundStyle(.white.opacity(0.5))
      ForEach(options) { option in
        Button {
          controller.select(option, in: options)
        } label: {
          HStack(spacing: 14) {
            Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
            Text(option.title)
          }
        }
        .buttonStyle(.pill)
        .focused(focus, equals: .panelItem("option-\(option.id)"))
      }
    }
    .focusSection()
  }
}
