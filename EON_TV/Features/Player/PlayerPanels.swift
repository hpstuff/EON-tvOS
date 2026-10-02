import SwiftUI
import EONKit

/// Bottom shelf shared by the schedule and channel panels: a title row and a row of glass cards
/// over the dimmed picture, running edge to edge. The content decides its own height, so cards
/// that grow with the viewer's text size never clip.
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
            .font(.headline.weight(.regular))
            .foregroundStyle(.white)
          if let subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(.white.opacity(0.6))
          }
          Spacer()
          Text("Press Back to close")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.45))
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.screenMargin)
        content()
      }
      .padding(.top, 34)
      .padding(.bottom, 44)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background {
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0),
          .init(color: .black.opacity(0.7), location: 0.4),
          .init(color: .black.opacity(0.9), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
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
          .font(.caption.weight(.regular))
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
                  ProgramCard(channel: channel, schedule: schedule, width: 320, showsChannelName: false, isDimmed: !playable)
                }
                .buttonStyle(.bare)
                .focused(focus, equals: .panelItem("schedule-\(schedule.id)"))
                .id(schedule.id)
              }
            }
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, 24)
            .padding(.bottom, 36)
          }
          // A horizontal scroll view takes all the height it is offered; hugging its row keeps
          // the sheet at the foot of the screen instead of stretching to the top.
          .fixedSize(horizontal: false, vertical: true)
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
          .padding(.top, 24)
          .padding(.bottom, 36)
        }
        .fixedSize(horizontal: false, vertical: true)
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

/// Track options for the current stream, the way the system player offers them: a glass
/// popover above the button that opened it, one list per button, with the chosen track ticked
/// and the focused row a white pill. Picking a row applies it at once and leaves the popover
/// open, so a viewer can compare tracks; Back, or moving focus out, closes it.
struct MediaOptionsPopover: View {
  let title: String
  let options: [PlayerController.MediaOption]
  let emptyMessage: String
  let onSelect: (PlayerController.MediaOption) -> Void
  let onClose: () -> Void
  var focus: FocusState<PlayerScreenContent.PlayerFocus?>.Binding

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
      if options.isEmpty {
        Button(action: onClose) {
          OptionRow(title: emptyMessage, isSelected: false, showsTick: false)
        }
        .buttonStyle(.bare)
        .focused(focus, equals: .panelItem("option-none"))
      }
      ForEach(options) { option in
        Button {
          onSelect(option)
        } label: {
          OptionRow(title: option.title, isSelected: option.isSelected)
        }
        .buttonStyle(.bare)
        .focused(focus, equals: .panelItem("option-\(option.id)"))
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 18)
    .frame(width: 520, alignment: .leading)
    .glassPanel(cornerRadius: 30)
    .focusSection()
    .onAppear {
      if let preferred = options.first(where: \.isSelected) ?? options.first {
        focusPanelItem(focus, preferred: "option-\(preferred.id)", fallback: options.first.map { "option-\($0.id)" })
      } else {
        focusPanelItem(focus, preferred: "option-none", fallback: nil)
      }
    }
  }
}

/// One row of a track popover: the tick for the chosen track, the title, and a white pill while
/// the row has focus.
private struct OptionRow: View {
  let title: String
  let isSelected: Bool
  var showsTick = true
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    HStack(spacing: 16) {
      if showsTick {
        Image(systemName: "checkmark")
          .font(.caption.weight(.semibold))
          .opacity(isSelected ? 1 : 0)
      }
      Text(title)
        .font(.caption)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .foregroundStyle(isFocused ? Theme.textOnFocus : .white)
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background {
      if isFocused {
        Capsule().fill(.white)
      }
    }
    .scaleEffect(isFocused ? 1.03 : 1)
    .animation(Theme.focusAnimation, value: isFocused)
  }
}
