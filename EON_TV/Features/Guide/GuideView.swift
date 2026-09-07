import SwiftUI
import Observation

/// Scroll geometry shared with the channel column and the time ruler. Kept in its own
/// observable so only those pieces re-render on every scroll frame, never the grid rows.
@Observable
final class GuideScrollState {
  var offsetX: CGFloat = 0
  var offsetY: CGFloat = 0
  var viewportHeight: CGFloat = 0
}

enum GuideMetrics {
  static let hourWidth: CGFloat = 640
  static let columnWidth: CGFloat = 280
  static let rowHeight: CGFloat = 96
  static let rowSpacing: CGFloat = 10
  static let rulerHeight: CGFloat = 44
  static let cellGap: CGFloat = 6
  static var rowPitch: CGFloat { rowHeight + rowSpacing }
  static var gridTopInset: CGFloat { rulerHeight + 8 }
  static var dayWidth: CGFloat { hourWidth * 24 }
  static var pointsPerMs: CGFloat { hourWidth / 3_600_000 }

  static func x(forMs ms: Int, dayStartMs: Int) -> CGFloat {
    CGFloat(ms - dayStartMs) * pointsPerMs
  }
}

/// The programme guide: channels down, time across, designed for a remote. Focus moves
/// between programmes (never by time slots), the focused programme is described in the header,
/// and the current time is always visible. Days and categories are one press away.
///
/// The channel column is a separate view that mirrors the grid's vertical offset, so a
/// programme can never sit hidden underneath it and steal focus.
struct GuideView: View {
  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock
  @Environment(FavoritesStore.self) private var favorites
  @Environment(PlaybackCoordinator.self) private var coordinator

  @State private var day: Date = Date().startOfTheDay
  @State private var filter: ChannelsView.Filter = .all
  @State private var scroll = GuideScrollState()
  @State private var position = ScrollPosition()
  @State private var focusedItem: ContentStore.ProgramItem?
  @State private var didScrollToNow = false
  @FocusState private var focus: GuideFocus?

  enum GuideFocus: Hashable {
    case day(Date)
    case filter(ChannelsView.Filter)
    case channel(Int)
    case cell(channel: Int, id: Int)
    case retry(Int)
  }

  private struct ScrollSnapshot: Equatable {
    var x: CGFloat
    var y: CGFloat
    var height: CGFloat
  }

  private var visibleChannels: [Channel] {
    switch filter {
    case .all: return store.channels
    case .favorites: return favorites.channels(in: store)
    case .category(let id): return store.categories.first { $0.id == id }?.channels ?? []
    }
  }

  private var dayStartMs: Int { day.timestamp }
  private var isToday: Bool { day == clock.dayStart }

  var body: some View {
    ZStack {
      AmbientBackdrop(url: focusedItem?.schedule.posterURL, intensity: 0.35)

      if store.hasChannels {
        VStack(alignment: .leading, spacing: 0) {
          header
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, Theme.contentTop)
          controls
            .padding(.top, 14)
          grid
            .padding(.top, 10)
        }
        .defaultFocus($focus, initialFocus)
      } else if case .failed(let message) = store.channelsState {
        StatusView(symbol: "list.bullet.rectangle", title: "The guide isn't available", message: message, actionTitle: "Try Again") {
          Task { await store.loadInitial() }
        }
      } else {
        ProgressView().tint(Theme.textSecondary)
      }
    }
    .onAppear(perform: handleAppear)
    .onChange(of: focus) { _, newValue in handleFocusChange(newValue) }
    .onChange(of: coordinator.guideTarget) { _, target in
      if let target { reveal(target) }
    }
    .onChange(of: clock.nowMs) { _, _ in store.recomputeShelves() }
  }

  // MARK: Header (focused programme)

  private var header: some View {
    let now = clock.nowMs
    return HStack(alignment: .top, spacing: 40) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Guide")
          .font(.screenTitle)
          .foregroundStyle(Theme.textPrimary)
        Text(day.relativeDayLabel() + " · " + day.formatted(.dateTime.day().month(.wide)))
          .font(.system(size: 24, weight: .medium))
          .foregroundStyle(Theme.textTertiary)
      }
      .frame(width: 360, alignment: .leading)

      if let item = focusedItem {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 14) {
            if item.schedule.isAiring(at: now) {
              LiveBadge(compact: true)
            } else if item.schedule.hasEnded(at: now), item.channel.isWithinCatchUpWindow(item.schedule, nowMs: now) {
              Tag(text: "CATCH UP")
            } else if item.schedule.isUpcoming(at: now) {
              Tag(text: "UPCOMING")
            }
            Text(item.channel.name)
              .font(.system(size: 24, weight: .semibold))
              .foregroundStyle(Theme.textSecondary)
            Text("\(item.schedule.timeRangeText) · \(item.schedule.durationMinutes) min")
              .font(.system(size: 24, weight: .medium))
              .foregroundStyle(Theme.textTertiary)
            if let subtitle = item.schedule.subtitleText {
              Text(subtitle)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
          }
          Text(item.schedule.title)
            .font(.system(size: 36, weight: .regular))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
          Text(item.schedule.descriptionText ?? " ")
            .font(.system(size: 23))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(item.schedule.id)
        .transition(.opacity)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Text("Move through the grid to see what's on.")
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
          Text("Select a programme to watch it live or from the start. Hold the touch surface for more options.")
            .font(.system(size: 23))
            .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
      }
    }
    .frame(height: 150, alignment: .top)
    .animation(Theme.crossfade, value: focusedItem?.schedule.id)
  }

  // MARK: Day and category controls

  private var controls: some View {
    HStack(spacing: 18) {
      ScrollView(.horizontal) {
        HStack(spacing: 12) {
          ForEach(store.guideDays, id: \.self) { candidate in
            Button {
              selectDay(candidate)
            } label: {
              FilterChipLabel(title: candidate.relativeDayLabel(), isSelected: candidate == day)
            }
            .buttonStyle(.bare)
            .focused($focus, equals: .day(candidate))
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
      }
      .frame(maxWidth: .infinity)
      .focusSection()

      Rectangle()
        .fill(Theme.stroke)
        .frame(width: 2, height: 36)

      ScrollView(.horizontal) {
        HStack(spacing: 12) {
          filterChip("All", .all)
          filterChip("Favorites", .favorites, symbol: "heart.fill")
          ForEach(store.browsableCategories) { category in
            filterChip(category.name, .category(category.id))
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
      }
      .frame(width: 720)
      .focusSection()
    }
    .padding(.horizontal, Theme.screenMargin - 20)
  }

  private func filterChip(_ title: String, _ value: ChannelsView.Filter, symbol: String? = nil) -> some View {
    Button {
      guard filter != value else { return }
      withAnimation(Theme.crossfade) { filter = value }
      focusedItem = nil
    } label: {
      FilterChipLabel(title: title, symbol: symbol, isSelected: filter == value)
    }
    .buttonStyle(.bare)
    .focused($focus, equals: .filter(value))
  }

  // MARK: Grid

  private var grid: some View {
    let channels = visibleChannels
    return HStack(alignment: .top, spacing: 0) {
      GuideChannelColumn(channels: channels, scroll: scroll, focus: $focus) { channel in
        coordinator.playLive(channel, lineup: channels)
      }
      .frame(width: GuideMetrics.columnWidth)
      .focusSection()

      ScrollView([.horizontal, .vertical]) {
        LazyVStack(alignment: .leading, spacing: GuideMetrics.rowSpacing) {
          ForEach(channels) { channel in
            GuideRow(
              channel: channel,
              day: day,
              focus: $focus,
              onSelectProgram: { schedule in select(schedule, on: channel, lineup: channels) },
              lineup: channels
            )
            .frame(width: GuideMetrics.dayWidth, height: GuideMetrics.rowHeight, alignment: .leading)
            .id(channel.id)
          }
        }
        .padding(.top, GuideMetrics.gridTopInset)
        .padding(.bottom, 60)
        .padding(.trailing, Theme.screenMargin)
      }
      .scrollPosition($position)
      .onScrollGeometryChange(for: ScrollSnapshot.self) { geometry in
        ScrollSnapshot(x: geometry.contentOffset.x, y: geometry.contentOffset.y, height: geometry.containerSize.height)
      } action: { _, snapshot in
        scroll.offsetX = max(0, snapshot.x)
        scroll.offsetY = max(0, snapshot.y)
        scroll.viewportHeight = snapshot.height
      }
      .overlay(alignment: .topLeading) {
        GuideRuler(day: day, scroll: scroll)
          .allowsHitTesting(false)
      }
      .overlay(alignment: .topLeading) {
        if isToday {
          GuideNowLine(day: day, scroll: scroll, nowMs: clock.nowMs)
            .allowsHitTesting(false)
        }
      }
      .focusSection()
    }
    .padding(.leading, Theme.screenMargin)
    .overlay {
      if channels.isEmpty {
        StatusView(
          symbol: filter == .favorites ? "heart" : "tv",
          title: filter == .favorites ? "No favorites yet" : "No channels here",
          message: filter == .favorites ? "Hold the touch surface on a channel and choose “Add to Favorites”." : "Nothing in this category is part of your subscription."
        )
      }
    }
  }

  // MARK: Behaviour

  /// Where focus lands when the viewer first moves down from the tab bar: what's on now on the
  /// first channel. Focus is never taken from the tab bar programmatically.
  private var initialFocus: GuideFocus {
    guard let channel = visibleChannels.first else { return .day(day) }
    if isToday, let current = store.nowPlaying(channel) {
      return .cell(channel: channel.id, id: current.id)
    }
    return .channel(channel.id)
  }

  private func handleAppear() {
    if day < (store.guideDays.first ?? day) || day > (store.guideDays.last ?? day) {
      day = clock.dayStart
    }
    if isToday && !didScrollToNow {
      didScrollToNow = true
      scrollToNow(animated: false)
    }
    if let target = coordinator.guideTarget { reveal(target) }
  }

  private func handleFocusChange(_ newValue: GuideFocus?) {
    switch newValue {
    case .cell(let channelID, let scheduleID):
      if let channel = store.channel(channelID),
         let schedule = store.schedules(for: channelID, day: day)?.first(where: { $0.id == scheduleID }) {
        focusedItem = ContentStore.ProgramItem(channel: channel, schedule: schedule)
      }
    case .channel(let channelID):
      if let channel = store.channel(channelID), let current = store.nowPlaying(channel) {
        focusedItem = ContentStore.ProgramItem(channel: channel, schedule: current)
      }
      revealRow(for: channelID)
    default:
      break
    }
  }

  /// The channel column can't scroll itself, so when one of its cells takes focus the grid
  /// is nudged just enough to bring that row fully into view; the column follows.
  private func revealRow(for channelID: Int) {
    guard let index = visibleChannels.firstIndex(where: { $0.id == channelID }), scroll.viewportHeight > 0 else { return }
    let rowTop = GuideMetrics.gridTopInset + CGFloat(index) * GuideMetrics.rowPitch
    let rowBottom = rowTop + GuideMetrics.rowHeight
    let visibleTop = scroll.offsetY + GuideMetrics.gridTopInset
    let visibleBottom = scroll.offsetY + scroll.viewportHeight
    var targetY: CGFloat?
    if rowTop < visibleTop {
      targetY = rowTop - GuideMetrics.gridTopInset
    } else if rowBottom > visibleBottom {
      targetY = rowBottom - scroll.viewportHeight + 24
    }
    if let targetY {
      withAnimation(.easeOut(duration: 0.2)) {
        position.scrollTo(x: scroll.offsetX, y: max(0, targetY))
      }
    }
  }

  private func selectDay(_ candidate: Date) {
    guard candidate != day else { return }
    withAnimation(Theme.crossfade) { day = candidate }
    focusedItem = nil
    if candidate == clock.dayStart {
      scrollToNow(animated: true)
    } else {
      // Other days open at prime time; mornings stay reachable by scrolling.
      position.scrollTo(x: GuideMetrics.hourWidth * 19, y: scroll.offsetY)
    }
  }

  private func scrollToNow(animated: Bool) {
    let nowX = GuideMetrics.x(forMs: clock.nowMs, dayStartMs: dayStartMs)
    let target = max(0, nowX - GuideMetrics.hourWidth * 0.5)
    if animated {
      withAnimation(Theme.crossfade) { position.scrollTo(x: target, y: scroll.offsetY) }
    } else {
      position.scrollTo(x: target, y: scroll.offsetY)
    }
  }

  private func reveal(_ channel: Channel) {
    coordinator.guideTarget = nil
    if !visibleChannels.contains(channel) { filter = .all }
    day = clock.dayStart
    scrollToNow(animated: false)
    Task {
      await store.ensureEPG(day: day, for: [channel])
      position.scrollTo(id: channel.id, anchor: .center)
      try? await Task.sleep(for: .milliseconds(120))
      if let current = store.nowPlaying(channel) {
        focus = .cell(channel: channel.id, id: current.id)
      } else {
        focus = .channel(channel.id)
      }
    }
  }

  private func select(_ schedule: Schedule, on channel: Channel, lineup: [Channel]) {
    coordinator.open(.init(channel: channel, schedule: schedule), nowMs: clock.nowMs, lineup: lineup)
  }
}

// MARK: - Channel column

/// Channel cells that mirror the grid's vertical scroll. Only the rows in view are built, so
/// following a 120 Hz scroll costs a handful of cells, not the whole line-up.
private struct GuideChannelColumn: View {
  let channels: [Channel]
  let scroll: GuideScrollState
  var focus: FocusState<GuideView.GuideFocus?>.Binding
  let onSelect: (Channel) -> Void

  @Environment(ContentStore.self) private var store

  var body: some View {
    GeometryReader { proxy in
      let pitch = GuideMetrics.rowPitch
      let first = max(0, Int((scroll.offsetY - GuideMetrics.gridTopInset) / pitch) - 1)
      let count = Int(proxy.size.height / pitch) + 3
      let last = min(channels.count, first + count)

      VStack(spacing: GuideMetrics.rowSpacing) {
        if first < last {
          ForEach(channels[first..<last]) { channel in
            Button {
              onSelect(channel)
            } label: {
              GuideChannelCellLabel(channel: channel, number: store.channelNumber(channel))
            }
            .buttonStyle(.bare)
            .frame(height: GuideMetrics.rowHeight)
            .focused(focus, equals: .channel(channel.id))
          }
        }
      }
      .frame(width: GuideMetrics.columnWidth - 12, alignment: .leading)
      .offset(y: GuideMetrics.gridTopInset + CGFloat(first) * pitch - scroll.offsetY)
    }
    .clipped()
  }
}

private struct GuideChannelCellLabel: View {
  let channel: Channel
  let number: Int
  @Environment(\.isFocused) private var isFocused

  var body: some View {
    HStack(spacing: 14) {
      Text(String(number))
        .font(.channelNumber)
        .foregroundStyle(isFocused ? Theme.textOnFocus.opacity(0.7) : Theme.textTertiary)
        .frame(width: 44, alignment: .trailing)
      ChannelLogo(channel: channel, height: 46, platter: false)
        .frame(width: 96)
      Text(channel.shortName)
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(isFocused ? Theme.textOnFocus : Theme.textSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .frame(width: GuideMetrics.columnWidth - 12, height: GuideMetrics.rowHeight)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(isFocused ? Color.white : Theme.backgroundElevated.opacity(0.9))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(isFocused ? Color.clear : Theme.stroke, lineWidth: 1)
    }
    .scaleEffect(isFocused ? 1.03 : 1)
    .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 20, x: 6)
    .animation(Theme.focusAnimation, value: isFocused)
  }
}

// MARK: - Row

private struct GuideRow: View {
  let channel: Channel
  let day: Date
  var focus: FocusState<GuideView.GuideFocus?>.Binding
  let onSelectProgram: (Schedule) -> Void
  let lineup: [Channel]

  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock

  private var dayStartMs: Int { day.timestamp }
  private var dayEndMs: Int { dayStartMs + 86_400_000 }

  var body: some View {
    let state = store.epgState(for: channel.id, day: day)
    ZStack(alignment: .leading) {
      switch state {
      case .loaded:
        programmes(store.schedules(for: channel.id, day: day) ?? [])
      case .failed:
        failedCell
      default:
        skeleton
      }
    }
    .frame(width: GuideMetrics.dayWidth, alignment: .leading)
    .task(id: day) {
      if case .idle = state {
        await store.ensureEPG(day: day, for: [channel])
      }
    }
  }

  @ViewBuilder
  private func programmes(_ list: [Schedule]) -> some View {
    let now = clock.nowMs
    let clipped = list.filter { $0.endTime > dayStartMs && $0.startTime < dayEndMs }
    if clipped.isEmpty {
      Text("No programme information")
        .font(.guideCell)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 24)
        .frame(width: GuideMetrics.hourWidth * 3, height: GuideMetrics.rowHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface.opacity(0.5)))
    } else {
      HStack(spacing: GuideMetrics.cellGap) {
        let firstStart = max(clipped[0].startTime, dayStartMs)
        if firstStart > dayStartMs {
          Color.clear.frame(width: GuideMetrics.x(forMs: firstStart, dayStartMs: dayStartMs) - GuideMetrics.cellGap)
        }
        ForEach(Array(clipped.enumerated()), id: \.element.id) { index, schedule in
          let start = max(schedule.startTime, dayStartMs)
          let end = min(schedule.endTime, dayEndMs)
          let width = max(24, CGFloat(end - start) * GuideMetrics.pointsPerMs - GuideMetrics.cellGap)
          Button {
            onSelectProgram(schedule)
          } label: {
            GuideCell(channel: channel, schedule: schedule, width: width, nowMs: now)
          }
          .buttonStyle(.guideCell)
          .focused(focus, equals: .cell(channel: channel.id, id: schedule.id))
          .onPlayPauseCommand { onSelectProgram(schedule) }
          .contextMenu {
            ProgramContextMenu(item: .init(channel: channel, schedule: schedule), lineup: lineup)
          }
          if index < clipped.count - 1 {
            let gap = CGFloat(clipped[index + 1].startTime - schedule.endTime) * GuideMetrics.pointsPerMs
            if gap > GuideMetrics.cellGap * 2 {
              Color.clear.frame(width: gap - GuideMetrics.cellGap)
            }
          }
        }
      }
    }
  }

  private var skeleton: some View {
    HStack(spacing: GuideMetrics.cellGap) {
      ForEach(0..<12, id: \.self) { index in
        SkeletonBlock(cornerRadius: 14)
          .frame(width: [420, 300, 640, 360, 520][(index + channel.id) % 5] - GuideMetrics.cellGap, height: GuideMetrics.rowHeight)
      }
    }
  }

  private var failedCell: some View {
    Button {
      Task { await store.retryFailedEPG(day: day) }
    } label: {
      Label("Couldn't load this channel's guide — try again", systemImage: "arrow.clockwise")
        .font(.guideCell)
    }
    .buttonStyle(.pill)
    .focused(focus, equals: .retry(channel.id))
    .padding(.leading, 12)
    .frame(height: GuideMetrics.rowHeight)
  }
}

/// One programme block. Reads the focus flag the button style publishes into the environment.
private struct GuideCell: View {
  let channel: Channel
  let schedule: Schedule
  let width: CGFloat
  let nowMs: Int
  @Environment(\.guideCellFocused) private var isFocused

  private var isAiring: Bool { schedule.isAiring(at: nowMs) }
  private var hasEnded: Bool { schedule.hasEnded(at: nowMs) }
  private var catchUpAvailable: Bool { hasEnded && channel.isWithinCatchUpWindow(schedule, nowMs: nowMs) }

  var body: some View {
    ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(background)
      if isAiring && !isFocused {
        GeometryReader { proxy in
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .frame(width: proxy.size.width * schedule.progress(at: nowMs))
        }
      }
      if width >= 90 {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 10) {
            if isAiring {
              Circle().fill(Theme.live).frame(width: 10, height: 10)
            } else if catchUpAvailable, width >= 200 {
              Image(systemName: "gobackward")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(isFocused ? Theme.textOnFocus.opacity(0.7) : Theme.textSecondary)
            }
            Text(schedule.title)
              .font(.guideCell)
              .foregroundStyle(isFocused ? Theme.textOnFocus : (hasEnded && !catchUpAvailable ? Theme.textTertiary : Theme.textPrimary))
              .lineLimit(1)
          }
          if width >= 220 {
            Text(schedule.timeRangeText)
              .font(.system(size: 20, weight: .medium))
              .foregroundStyle(isFocused ? Theme.textOnFocus.opacity(0.65) : Theme.textTertiary)
              .lineLimit(1)
          }
        }
        .padding(.horizontal, 20)
      }
    }
    .frame(width: width, height: GuideMetrics.rowHeight)
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(isAiring && !isFocused ? Color.white.opacity(0.38) : Color.white.opacity(0.06), lineWidth: isAiring && !isFocused ? 1.5 : 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var background: Color {
    if isFocused { return .white }
    if isAiring { return Color.white.opacity(0.14) }
    if hasEnded { return Color.white.opacity(catchUpAvailable ? 0.07 : 0.04) }
    return Color.white.opacity(0.09)
  }
}

/// Half-hour time ruler pinned above the programme area, scrolling horizontally with it.
private struct GuideRuler: View {
  let day: Date
  let scroll: GuideScrollState

  var body: some View {
    GeometryReader { proxy in
      HStack(spacing: 0) {
        ForEach(0..<48, id: \.self) { slot in
          let date = day.addingTimeInterval(TimeInterval(slot) * 1800)
          HStack(spacing: 10) {
            Rectangle().fill(Theme.stroke).frame(width: 2, height: 16)
            Text(date.shortTime)
              .font(.guideRuler)
              .foregroundStyle(Theme.textSecondary)
          }
          .frame(width: GuideMetrics.hourWidth / 2, alignment: .leading)
        }
      }
      .offset(x: -scroll.offsetX)
      .frame(width: proxy.size.width, alignment: .leading)
      .clipped()
    }
    .frame(height: GuideMetrics.rulerHeight)
    .background(alignment: .top) {
      VStack(spacing: 0) {
        Theme.background.opacity(0.97)
          .frame(height: GuideMetrics.rulerHeight + 4)
        LinearGradient(colors: [Theme.background.opacity(0.97), .clear], startPoint: .top, endPoint: .bottom)
          .frame(height: 14)
      }
    }
  }
}

/// The vertical "now" marker across the programme area.
private struct GuideNowLine: View {
  let day: Date
  let scroll: GuideScrollState
  let nowMs: Int

  var body: some View {
    GeometryReader { proxy in
      let x = GuideMetrics.x(forMs: nowMs, dayStartMs: day.timestamp) - scroll.offsetX
      if x >= -1, x <= proxy.size.width + 1 {
        VStack(spacing: 0) {
          Text(nowMs.dateFromMs.shortTime)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.textOnFocus)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white))
          Rectangle()
            .fill(Theme.spectrumVertical)
            .frame(width: 3)
        }
        .frame(width: 80)
        .position(x: x, y: proxy.size.height / 2 + GuideMetrics.rulerHeight / 2)
        .frame(height: proxy.size.height)
      }
    }
  }
}
