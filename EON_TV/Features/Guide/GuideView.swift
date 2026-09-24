import SwiftUI
import EONKit
import Observation

/// Scroll geometry shared with the channel column and the time ruler. Kept in its own
/// observable so only those pieces re-render on every scroll frame, never the grid rows.
///
/// The rows follow `window` instead: the hours of the day worth building cells for. A row's
/// cells are the costly part of the guide (every one is a focusable button with a context
/// menu), so only those near the viewport exist, and the window moves in whole hours so rows
/// re-evaluate a couple of times per screen of scrolling rather than on every frame.
@Observable
final class GuideScrollState {
  var offsetX: CGFloat = 0
  var offsetY: CGFloat = 0
  var viewportWidth: CGFloat = 1_640
  var viewportHeight: CGFloat = 0
  /// Milliseconds from the start of the day, snapped to whole hours.
  private(set) var window: Range<Int> = 0..<0

  func updateWindow(metrics: GuideMetrics) {
    let fresh = metrics.buildWindow(offsetX: offsetX, viewportWidth: viewportWidth)
    if fresh != window { window = fresh }
  }

  /// Called ahead of a programmatic scroll so the rows at the destination are built in the
  /// same pass that moves there, instead of a frame later. Only the window moves; the offset
  /// itself keeps following the scroll view, so the ruler never runs ahead of the grid.
  func anticipate(offsetX target: CGFloat, metrics: GuideMetrics) {
    let fresh = metrics.buildWindow(offsetX: max(0, target), viewportWidth: viewportWidth)
    if fresh != window { window = fresh }
  }
}

/// Grid geometry. Everything scales with the viewer's text size (`scale` is the caption text
/// style's factor, capped) so an hour of guide keeps about the same number of characters per
/// cell whether text is default or accessibility sized.
struct GuideMetrics: Equatable {
  var scale: CGFloat = 1

  static let dayMs = 86_400_000
  static let hourMs = 3_600_000

  var hourWidth: CGFloat { 640 * scale }
  var columnWidth: CGFloat { 280 * scale }
  var rowHeight: CGFloat { 96 * scale }
  var rowSpacing: CGFloat { 10 }
  var rulerHeight: CGFloat { 44 * scale }
  var cellGap: CGFloat { 6 }
  var rowPitch: CGFloat { rowHeight + rowSpacing }
  var gridTopInset: CGFloat { rulerHeight + 8 }
  var dayWidth: CGFloat { hourWidth * 24 }
  var pointsPerMs: CGFloat { hourWidth / CGFloat(Self.hourMs) }

  func x(forMs ms: Int, dayStartMs: Int) -> CGFloat {
    CGFloat(ms - dayStartMs) * pointsPerMs
  }

  /// The span of the day to build cells for at this horizontal offset: the viewport plus an
  /// hour either side, widened to whole hours.
  func buildWindow(offsetX: CGFloat, viewportWidth: CGFloat) -> Range<Int> {
    let hour = Self.hourMs
    let startMs = max(0, Int(((offsetX - hourWidth) / pointsPerMs).rounded()))
    let endMs = min(Self.dayMs, Int(((offsetX + viewportWidth + hourWidth) / pointsPerMs).rounded()))
    let lower = (startMs / hour) * hour
    let upper = min(Self.dayMs, ((endMs + hour - 1) / hour) * hour)
    return lower..<max(lower, upper)
  }
}

extension Array where Element == Schedule {
  /// Indices of the programmes to build for a window of the day, given a list sorted by start
  /// time: every programme that overlaps the window plus one neighbour on each side, so focus
  /// can always step left or right from a programme at the window's edge, however long it is.
  /// `nil` when nothing in the list touches the window.
  func guideRange(dayStartMs: Int, window: Range<Int>) -> Range<Int>? {
    let windowStart = dayStartMs + window.lowerBound
    let windowEnd = dayStartMs + window.upperBound
    var first: Int?
    var last: Int?
    for (index, schedule) in enumerated() where schedule.endTime > windowStart && schedule.startTime < windowEnd {
      if first == nil { first = index }
      last = index
    }
    guard let first, let last else { return nil }
    return Swift.max(0, first - 1)..<Swift.min(count, last + 2)
  }
}

private struct GuideMetricsKey: EnvironmentKey {
  static let defaultValue = GuideMetrics()
}

extension EnvironmentValues {
  var guideMetrics: GuideMetrics {
    get { self[GuideMetricsKey.self] }
    set { self[GuideMetricsKey.self] = newValue }
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
  @ScaledMetric(relativeTo: .caption) private var textScale: CGFloat = 1

  @State private var day: Date = Date().startOfTheDay
  @State private var filter: ChannelsView.Filter = .all
  @State private var scroll = GuideScrollState()
  @State private var position = ScrollPosition()
  @State private var focusedItem: ContentStore.ProgramItem?
  @State private var scrolledDay: Date?
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
    var width: CGFloat
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
  private var metrics: GuideMetrics { GuideMetrics(scale: min(textScale, 1.8)) }

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
    .environment(\.guideMetrics, metrics)
    .onAppear(perform: handleAppear)
    .onChange(of: coordinator.selectedSection, initial: true) { _, section in
      if section == .guide { showToday() }
    }
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
          .font(.caption)
          .foregroundStyle(Theme.textTertiary)
      }
      .frame(width: 360 * metrics.scale, alignment: .leading)

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
              .font(.caption.weight(.semibold))
              .foregroundStyle(Theme.textSecondary)
            Text("\(item.schedule.timeRangeText) · \(item.schedule.durationMinutes) min")
              .font(.caption)
              .foregroundStyle(Theme.textTertiary)
            if let subtitle = item.schedule.subtitleText {
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
          }
          .lineLimit(1)
          Text(item.schedule.title)
            .font(.headline.weight(.regular))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
          Text(item.schedule.descriptionText ?? " ")
            .font(.caption.weight(.regular))
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
            .font(.body)
            .foregroundStyle(Theme.textSecondary)
          Text("Select a programme to watch it live or from the start. Hold the touch surface for more options.")
            .font(.caption.weight(.regular))
            .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
      }
    }
    .frame(minHeight: 150, alignment: .top)
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
            .buttonStyle(.glass)
            .focused($focus, equals: .day(candidate))
          }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
      }
      // Today is the last chip now that the guide stops there, so the strip has to open at its
      // end rather than at the oldest catch-up day.
      .scrollPosition(id: $scrolledDay, anchor: .trailing)
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
      // Categories take a fixed share so the day rail keeps room when chips grow with text size.
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
    .buttonStyle(.glass)
    .focused($focus, equals: .filter(value))
  }

  // MARK: Grid

  private var grid: some View {
    let channels = visibleChannels
    return HStack(alignment: .top, spacing: 0) {
      GuideChannelColumn(channels: channels, scroll: scroll, focus: $focus) { channel in
        coordinator.playLive(channel, lineup: channels)
      }
      .frame(width: metrics.columnWidth)
      .focusSection()

      ScrollView([.horizontal, .vertical]) {
        LazyVStack(alignment: .leading, spacing: metrics.rowSpacing) {
          ForEach(channels) { channel in
            GuideRow(
              channel: channel,
              day: day,
              scroll: scroll,
              focus: $focus,
              onSelectProgram: { schedule in select(schedule, on: channel, lineup: channels) },
              lineup: channels
            )
            .equatable()
            .frame(width: metrics.dayWidth, height: metrics.rowHeight, alignment: .leading)
            .id(channel.id)
          }
        }
        .padding(.top, metrics.gridTopInset)
        .padding(.bottom, 60)
        .padding(.trailing, Theme.screenMargin)
      }
      .scrollPosition($position)
      .onScrollGeometryChange(for: ScrollSnapshot.self) { geometry in
        ScrollSnapshot(
          x: geometry.contentOffset.x,
          y: geometry.contentOffset.y,
          width: geometry.containerSize.width,
          height: geometry.containerSize.height
        )
      } action: { _, snapshot in
        scroll.offsetX = max(0, snapshot.x)
        scroll.offsetY = max(0, snapshot.y)
        scroll.viewportWidth = snapshot.width
        scroll.viewportHeight = snapshot.height
        scroll.updateWindow(metrics: metrics)
      }
      // One handler for the whole grid rather than a command responder on every cell: play/pause
      // opens the focused programme.
      .onPlayPauseCommand {
        guard case .cell = focus, let item = focusedItem else { return }
        select(item.schedule, on: item.channel, lineup: channels)
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

  /// Where focus lands when the viewer enters the guide from the sidebar: what's on now on the
  /// first channel. Focus is never taken from the sidebar programmatically.
  private var initialFocus: GuideFocus {
    guard let channel = visibleChannels.first else { return .day(day) }
    if isToday, let current = store.nowPlaying(channel) {
      return .cell(channel: channel.id, id: current.id)
    }
    return .channel(channel.id)
  }

  private func handleAppear() {
    scrolledDay = day
    if let target = coordinator.guideTarget { reveal(target) }
  }

  /// The guide always opens on today, at what's on now: a day picked earlier in the session
  /// shouldn't still be showing the next time the viewer enters the tab. Skipped when a channel
  /// is being revealed from elsewhere, since that already places the grid itself.
  private func showToday() {
    guard coordinator.guideTarget == nil else { return }
    if day != clock.dayStart {
      day = clock.dayStart
      focusedItem = nil
    }
    scrolledDay = day
    scrollToNow(animated: false)
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
    let rowTop = metrics.gridTopInset + CGFloat(index) * metrics.rowPitch
    let rowBottom = rowTop + metrics.rowHeight
    let visibleTop = scroll.offsetY + metrics.gridTopInset
    let visibleBottom = scroll.offsetY + scroll.viewportHeight
    var targetY: CGFloat?
    if rowTop < visibleTop {
      targetY = rowTop - metrics.gridTopInset
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
      let target = metrics.hourWidth * 19
      scroll.anticipate(offsetX: target, metrics: metrics)
      position.scrollTo(x: target, y: scroll.offsetY)
    }
  }

  private func scrollToNow(animated: Bool) {
    let nowX = metrics.x(forMs: clock.nowMs, dayStartMs: dayStartMs)
    let target = max(0, nowX - metrics.hourWidth * 0.5)
    scroll.anticipate(offsetX: target, metrics: metrics)
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

  @Environment(\.guideMetrics) private var metrics

  var body: some View {
    GeometryReader { proxy in
      let pitch = metrics.rowPitch
      let first = max(0, Int((scroll.offsetY - metrics.gridTopInset) / pitch) - 1)
      let count = Int(proxy.size.height / pitch) + 3
      let last = min(channels.count, first + count)

      GuideChannelCells(channels: first < last ? Array(channels[first..<last]) : [], focus: focus, onSelect: onSelect)
        .equatable()
        .offset(y: metrics.gridTopInset + CGFloat(first) * pitch - scroll.offsetY)
    }
    .clipped()
  }
}

/// The channel cells currently in view. A scroll frame that keeps the same rows on screen only
/// moves this view; its cells are rebuilt when a row enters or leaves.
private struct GuideChannelCells: View, Equatable {
  let channels: [Channel]
  var focus: FocusState<GuideView.GuideFocus?>.Binding
  let onSelect: (Channel) -> Void

  @Environment(ContentStore.self) private var store
  @Environment(\.guideMetrics) private var metrics

  static func == (lhs: GuideChannelCells, rhs: GuideChannelCells) -> Bool {
    lhs.channels == rhs.channels
  }

  var body: some View {
    VStack(spacing: metrics.rowSpacing) {
      ForEach(channels) { channel in
        Button {
          onSelect(channel)
        } label: {
          GuideChannelCellLabel(channel: channel, number: store.channelNumber(channel))
        }
        .buttonStyle(.bare)
        .frame(height: metrics.rowHeight)
        .focused(focus, equals: .channel(channel.id))
      }
    }
    .frame(width: metrics.columnWidth - 12, alignment: .leading)
  }
}

private struct GuideChannelCellLabel: View {
  let channel: Channel
  let number: Int
  @Environment(\.isFocused) private var isFocused
  @Environment(\.guideMetrics) private var metrics

  var body: some View {
    HStack(spacing: 14) {
      Text(String(number))
        .font(.channelNumber)
        .foregroundStyle(isFocused ? Theme.textOnFocus.opacity(0.7) : Theme.textTertiary)
        .frame(width: 44 * metrics.scale, alignment: .trailing)
      ChannelLogo(channel: channel, height: metrics.rowHeight * 0.48, platter: false)
        .frame(width: 96 * metrics.scale)
      Text(channel.shortName)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(isFocused ? Theme.textOnFocus : Theme.textSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .frame(width: metrics.columnWidth - 12, height: metrics.rowHeight)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(isFocused ? Color.white : Theme.backgroundElevated.opacity(0.9))
    }
    // A dozen cells follow every scroll frame; only the focused one carries a shadow, so the
    // others cost nothing beyond their platter.
    .background {
      if isFocused {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.black.opacity(0.5))
          .blur(radius: 20)
          .offset(x: 6)
          .transition(.opacity)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(isFocused ? Color.clear : Theme.stroke, lineWidth: 1)
    }
    .scaleEffect(isFocused ? 1.03 : 1)
    .animation(Theme.focusAnimation, value: isFocused)
  }
}

// MARK: - Row

/// One channel's day. Every focus move re-evaluates the guide (the header describes the focused
/// programme), so rows compare equal by channel, day and line-up and are applied with
/// `.equatable()`: a row is rebuilt only when its guide data, the clock or the build window
/// changes, never because focus moved somewhere else in the grid.
///
/// Only the programmes inside the scroll state's window exist as cells — the viewport, an hour
/// either side, and one neighbour beyond that so focus can always step off the edge. The rest of
/// the day is empty space at the right offsets, so the row keeps the full day's width and cells
/// never move when the window does.
private struct GuideRow: View, Equatable {
  let channel: Channel
  let day: Date
  let scroll: GuideScrollState
  var focus: FocusState<GuideView.GuideFocus?>.Binding
  let onSelectProgram: (Schedule) -> Void
  let lineup: [Channel]

  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock
  @Environment(\.guideMetrics) private var metrics

  static func == (lhs: GuideRow, rhs: GuideRow) -> Bool {
    lhs.channel == rhs.channel && lhs.day == rhs.day && lhs.lineup == rhs.lineup
  }

  /// A programme placed in the row with its index in the day's list, so the gap to the next
  /// programme is known without searching for it.
  private struct Placed: Identifiable {
    let index: Int
    let schedule: Schedule
    var id: Int { schedule.id }
  }

  private var dayStartMs: Int { day.timestamp }
  private var dayEndMs: Int { dayStartMs + GuideMetrics.dayMs }

  var body: some View {
    let state = store.epgState(for: channel.id, day: day)
    let window = scroll.window
    ZStack(alignment: .leading) {
      switch state {
      case .loaded:
        programmes(store.schedules(for: channel.id, day: day) ?? [], window: window)
      case .failed:
        failedCell(window: window)
      default:
        skeleton(window: window)
      }
    }
    .frame(width: metrics.dayWidth, alignment: .leading)
    .task(id: day) {
      if case .idle = state {
        await store.ensureEPG(day: day, for: [channel])
      }
    }
  }

  @ViewBuilder
  private func programmes(_ list: [Schedule], window: Range<Int>) -> some View {
    let now = clock.nowMs
    let dayList = list.filter { $0.endTime > dayStartMs && $0.startTime < dayEndMs }
    if let range = dayList.guideRange(dayStartMs: dayStartMs, window: window) {
      HStack(spacing: metrics.cellGap) {
        let firstStart = max(dayList[range.lowerBound].startTime, dayStartMs)
        if firstStart > dayStartMs {
          Color.clear.frame(width: metrics.x(forMs: firstStart, dayStartMs: dayStartMs) - metrics.cellGap)
        }
        ForEach(range.map { Placed(index: $0, schedule: dayList[$0]) }) { placed in
          let schedule = placed.schedule
          let start = max(schedule.startTime, dayStartMs)
          let end = min(schedule.endTime, dayEndMs)
          let width = max(24, CGFloat(end - start) * metrics.pointsPerMs - metrics.cellGap)
          Button {
            onSelectProgram(schedule)
          } label: {
            GuideCell(channel: channel, schedule: schedule, width: width, nowMs: now)
          }
          .buttonStyle(.guideCell)
          .focused(focus, equals: .cell(channel: channel.id, id: schedule.id))
          .contextMenu {
            ProgramContextMenu(item: .init(channel: channel, schedule: schedule), lineup: lineup)
          }
          if placed.index + 1 < dayList.count {
            let gap = CGFloat(dayList[placed.index + 1].startTime - schedule.endTime) * metrics.pointsPerMs
            if gap > metrics.cellGap * 2 {
              Color.clear.frame(width: gap - metrics.cellGap)
            }
          }
        }
      }
    } else {
      Text("No programme information")
        .font(.guideCell)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 24)
        .frame(width: metrics.hourWidth * 3, height: metrics.rowHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface.opacity(0.5)))
        .padding(.leading, noticeLeading(in: window))
    }
  }

  /// Where a notice standing in for programmes goes: centred on the window, which keeps it on
  /// screen wherever the viewer has scrolled to instead of at the start of the day.
  private func noticeLeading(in window: Range<Int>) -> CGFloat {
    let start = CGFloat(window.lowerBound) * metrics.pointsPerMs
    let span = CGFloat(window.count) * metrics.pointsPerMs
    return start + max(0, (span - metrics.hourWidth * 3) / 2)
  }

  /// Placeholder blocks covering the window while this channel's guide loads.
  private func skeleton(window: Range<Int>) -> some View {
    let pattern: [CGFloat] = [420, 300, 640, 360, 520]
    let start = CGFloat(window.lowerBound) * metrics.pointsPerMs
    let span = CGFloat(window.count) * metrics.pointsPerMs
    var blocks: [CGFloat] = []
    var covered: CGFloat = 0
    while covered < span {
      let width = pattern[(blocks.count + channel.id) % pattern.count] * metrics.scale
      blocks.append(width - metrics.cellGap)
      covered += width
    }
    return HStack(spacing: metrics.cellGap) {
      if start > 0 {
        Color.clear.frame(width: start - metrics.cellGap)
      }
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, width in
        SkeletonBlock(cornerRadius: 14)
          .frame(width: width, height: metrics.rowHeight)
      }
    }
  }

  private func failedCell(window: Range<Int>) -> some View {
    Button {
      Task { await store.retryFailedEPG(day: day) }
    } label: {
      Label("Couldn't load this channel's guide — try again", systemImage: "arrow.clockwise")
    }
    .buttonStyle(.glass)
    .focused(focus, equals: .retry(channel.id))
    .padding(.leading, noticeLeading(in: window) + 12)
    .frame(height: metrics.rowHeight)
  }
}

/// One programme block. Reads the focus flag the button style publishes into the environment.
private struct GuideCell: View {
  let channel: Channel
  let schedule: Schedule
  let width: CGFloat
  let nowMs: Int
  @Environment(\.guideCellFocused) private var isFocused
  @Environment(\.guideMetrics) private var metrics

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
      if width >= 90 * metrics.scale {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 10) {
            if isAiring {
              Circle().fill(Theme.live).frame(width: 10 * metrics.scale, height: 10 * metrics.scale)
            } else if catchUpAvailable, width >= 200 * metrics.scale {
              Image(systemName: "gobackward")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isFocused ? Theme.textOnFocus.opacity(0.7) : Theme.textSecondary)
            }
            Text(schedule.title)
              .font(.guideCell)
              .foregroundStyle(isFocused ? Theme.textOnFocus : (hasEnded && !catchUpAvailable ? Theme.textTertiary : Theme.textPrimary))
              .lineLimit(1)
          }
          if width >= 220 * metrics.scale {
            Text(schedule.timeRangeText)
              .font(.caption2)
              .foregroundStyle(isFocused ? Theme.textOnFocus.opacity(0.65) : Theme.textTertiary)
              .lineLimit(1)
          }
        }
        .padding(.horizontal, 20)
      }
    }
    .frame(width: width, height: metrics.rowHeight)
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

/// Half-hour time ruler pinned above the programme area, scrolling horizontally with it. The
/// marks are a separate view compared by day, so a scroll frame moves them without rebuilding
/// (and re-formatting) forty-eight labels.
private struct GuideRuler: View {
  let day: Date
  let scroll: GuideScrollState
  @Environment(\.guideMetrics) private var metrics

  var body: some View {
    GeometryReader { proxy in
      GuideRulerMarks(day: day)
        .equatable()
        .offset(x: -scroll.offsetX)
        .frame(width: proxy.size.width, alignment: .leading)
        .clipped()
    }
    .frame(height: metrics.rulerHeight)
    .background(alignment: .top) {
      VStack(spacing: 0) {
        Theme.background.opacity(0.97)
          .frame(height: metrics.rulerHeight + 4)
        LinearGradient(colors: [Theme.background.opacity(0.97), .clear], startPoint: .top, endPoint: .bottom)
          .frame(height: 14)
      }
    }
  }
}

/// The forty-eight half-hour marks of one day.
private struct GuideRulerMarks: View, Equatable {
  let day: Date
  @Environment(\.guideMetrics) private var metrics

  static func == (lhs: GuideRulerMarks, rhs: GuideRulerMarks) -> Bool {
    lhs.day == rhs.day
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(0..<48, id: \.self) { slot in
        let date = day.addingTimeInterval(TimeInterval(slot) * 1800)
        HStack(spacing: 10) {
          Rectangle().fill(Theme.stroke).frame(width: 2, height: 16)
          Text(date.shortTime)
            .font(.guideRuler)
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: metrics.hourWidth / 2, alignment: .leading)
      }
    }
  }
}

/// The vertical "now" marker across the programme area.
private struct GuideNowLine: View {
  let day: Date
  let scroll: GuideScrollState
  let nowMs: Int
  @Environment(\.guideMetrics) private var metrics

  var body: some View {
    GeometryReader { proxy in
      let x = metrics.x(forMs: nowMs, dayStartMs: day.timestamp) - scroll.offsetX
      if x >= -1, x <= proxy.size.width + 1 {
        VStack(spacing: 0) {
          Text(nowMs.dateFromMs.shortTime)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textOnFocus)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white))
          Rectangle()
            .fill(Theme.spectrumVertical)
            .frame(width: 3)
        }
        .frame(width: 100 * metrics.scale)
        .position(x: x, y: proxy.size.height / 2 + metrics.rulerHeight / 2)
        .frame(height: proxy.size.height)
      }
    }
  }
}
