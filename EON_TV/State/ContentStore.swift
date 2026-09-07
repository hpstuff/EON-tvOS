import Foundation
import Observation

/// Central content state: the channel line-up, categories and the programme guide.
///
/// The guide is loaded progressively in stable chunks of the default channel order (so the
/// SDK's URL-keyed cache keeps hitting), and every "on now / up next / catch up" shelf is
/// derived here from the live clock so screens update in place instead of reloading.
@Observable
final class ContentStore {
  enum LoadState: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  struct ChunkKey: Hashable {
    let day: Date
    let index: Int
  }

  struct OnNowItem: Identifiable, Equatable {
    let channel: Channel
    let schedule: Schedule?
    var id: Int { channel.id }
  }

  struct ProgramItem: Identifiable, Equatable {
    let channel: Channel
    let schedule: Schedule
    var id: Int { schedule.id }
  }

  struct Shelves: Equatable {
    var onNow: [OnNowItem] = []
    var upNext: [ProgramItem] = []
    var catchUp: [ProgramItem] = []
  }

  struct SearchResults {
    var channels: [Channel] = []
    var onNow: [ProgramItem] = []
    var upcoming: [ProgramItem] = []
    var catchUp: [ProgramItem] = []
    var isEmpty: Bool { channels.isEmpty && onNow.isEmpty && upcoming.isEmpty && catchUp.isEmpty }
  }

  static let chunkSize = 10
  private static let maxConcurrentChunks = 4
  private static let keptDays = 9

  private let backend: Backend
  let clock: LiveClock

  // Line-up
  private(set) var categories: [ChannelCategory] = []
  private(set) var channels: [Channel] = []
  private(set) var channelsByID: [Int: Channel] = [:]
  private(set) var channelNumbers: [Int: Int] = [:]
  private(set) var channelsState: LoadState = .idle
  private var lastChannelsRefresh: Date?

  // Guide: day start → channel id → programmes sorted by start time
  private(set) var epg: [Date: [Int: [Schedule]]] = [:]
  private var loadedChunks: Set<ChunkKey> = []
  private var loadingChunks: Set<ChunkKey> = []
  private var failedChunks: Set<ChunkKey> = []
  private(set) var todayLoadedFraction: Double = 0

  // Derived
  private(set) var shelves = Shelves()
  private var nowByChannel: [Int: Schedule] = [:]
  private var nextByChannel: [Int: Schedule] = [:]
  private var lastShelfNow: Int = 0

  init(backend: Backend, clock: LiveClock) {
    self.backend = backend
    self.clock = clock
    clock.onDayChange = { [weak self] day in self?.handleDayChange(day) }
  }

  func stop() {
    clock.onDayChange = nil
  }

  // MARK: Line-up

  var hasChannels: Bool { !channels.isEmpty }

  /// Categories worth browsing: the default list is the full line-up, so it's not repeated.
  var browsableCategories: [ChannelCategory] {
    categories.filter { !$0.defaultList && !$0.channels.isEmpty }
  }

  func loadInitial() async {
    await loadChannels()
    guard hasChannels else { return }
    await ensureEPG(day: clock.dayStart, for: channels)
  }

  func loadChannels(silently: Bool = false) async {
    if !silently { channelsState = .loading }
    do {
      let fetched = try await backend.channels.getCategories()
      apply(categories: fetched)
      channelsState = .loaded
      lastChannelsRefresh = Date()
    } catch {
      if channels.isEmpty || !silently {
        channelsState = .failed(ErrorPresenter.message(for: error, context: .content))
      }
    }
  }

  private func apply(categories fetched: [ChannelCategory]) {
    let lineup: [Channel]
    if let defaultList = fetched.first(where: { $0.defaultList }) {
      lineup = defaultList.channels
    } else {
      var seen = Set<Int>()
      lineup = fetched.flatMap(\.channels).filter { seen.insert($0.id).inserted }
    }
    let sameLineup = lineup.map(\.id) == channels.map(\.id)
    let sameCategories = fetched == categories
    guard !(sameLineup && sameCategories) else { return }

    categories = fetched
    channels = lineup
    channelsByID = Dictionary(lineup.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    channelNumbers = Dictionary(uniqueKeysWithValues: lineup.enumerated().map { ($1.id, $0 + 1) })
    if !sameLineup {
      // Chunk membership follows the line-up, so previously loaded guide chunks no longer line up.
      loadedChunks.removeAll()
      failedChunks.removeAll()
      Task { await ensureEPG(day: clock.dayStart, for: channels) }
    }
    recomputeShelves(force: true)
  }

  func channel(_ id: Int) -> Channel? { channelsByID[id] }

  func channelNumber(_ channel: Channel) -> Int { channelNumbers[channel.id] ?? 0 }

  func channels(in category: ChannelCategory?) -> [Channel] {
    guard let category else { return channels }
    return category.channels
  }

  // MARK: Guide

  func chunkIndex(for channelID: Int) -> Int? {
    guard let number = channelNumbers[channelID] else { return nil }
    return (number - 1) / Self.chunkSize
  }

  func schedules(for channelID: Int, day: Date) -> [Schedule]? {
    epg[day.startOfTheDay]?[channelID]
  }

  func epgState(for channelID: Int, day: Date) -> LoadState {
    guard let index = chunkIndex(for: channelID) else { return .failed("Unknown channel") }
    let key = ChunkKey(day: day.startOfTheDay, index: index)
    if loadedChunks.contains(key) { return .loaded }
    if loadingChunks.contains(key) { return .loading }
    if failedChunks.contains(key) { return .failed("Couldn't load the guide.") }
    return .idle
  }

  /// Loads any guide chunks still missing for these channels on this day.
  func ensureEPG(day: Date, for wanted: [Channel]) async {
    let day = day.startOfTheDay
    let indices = Set(wanted.compactMap { chunkIndex(for: $0.id) })
    let missing = indices
      .map { ChunkKey(day: day, index: $0) }
      .filter { !loadedChunks.contains($0) && !loadingChunks.contains($0) }
      .sorted { $0.index < $1.index }
    guard !missing.isEmpty else { return }

    for key in missing {
      loadingChunks.insert(key)
      failedChunks.remove(key)
    }

    await withTaskGroup(of: Void.self) { group in
      var iterator = missing.makeIterator()
      var running = 0
      while running < Self.maxConcurrentChunks, let key = iterator.next() {
        group.addTask { await self.loadChunk(key) }
        running += 1
      }
      for await _ in group {
        if let key = iterator.next() {
          group.addTask { await self.loadChunk(key) }
        }
      }
    }
  }

  func retryFailedEPG(day: Date) async {
    let day = day.startOfTheDay
    let failed = failedChunks.filter { $0.day == day }
    guard !failed.isEmpty else { return }
    let ids = failed.flatMap { key in channels.dropFirst(key.index * Self.chunkSize).prefix(Self.chunkSize) }
    failedChunks.subtract(failed)
    await ensureEPG(day: day, for: Array(ids))
  }

  private func loadChunk(_ key: ChunkKey) async {
    let start = key.index * Self.chunkSize
    guard start < channels.count else {
      loadingChunks.remove(key)
      return
    }
    let slice = Array(channels[start..<min(start + Self.chunkSize, channels.count)])
    do {
      let result = try await backend.epg.getSchedule(forChannels: slice, forDay: key.day)
      var dayMap = epg[key.day] ?? [:]
      for channel in slice {
        let programmes = (result[channel.id] ?? []).sorted { $0.startTime < $1.startTime }
        dayMap[channel.id] = programmes
      }
      epg[key.day] = dayMap
      loadedChunks.insert(key)
    } catch {
      failedChunks.insert(key)
    }
    loadingChunks.remove(key)
    updateTodayFraction()
    recomputeShelves(force: true)
  }

  private func updateTodayFraction() {
    let today = clock.dayStart
    let total = max(1, (channels.count + Self.chunkSize - 1) / Self.chunkSize)
    let done = loadedChunks.filter { $0.day == today }.count
    todayLoadedFraction = Double(done) / Double(total)
  }

  /// The programme airing on `channelID` at an absolute time, if that day is loaded.
  func schedule(at ms: Int, channelID: Int) -> Schedule? {
    let day = ms.dateFromMs.startOfTheDay
    return epg[day]?[channelID]?.first { $0.startTime <= ms && ms < $0.endTime }
  }

  func schedule(withID id: Int, channelID: Int) -> Schedule? {
    for (_, dayMap) in epg {
      if let match = dayMap[channelID]?.first(where: { $0.id == id }) { return match }
    }
    return nil
  }

  /// Guide days offered to the viewer: as far back as catch-up reaches, one week ahead.
  var guideDays: [Date] {
    let calendar = Calendar.current
    let today = clock.dayStart
    let maxWindow = channels.map(\.catchUpWindow).max() ?? 0
    let backDays = min(7, Int(maxWindow / 86_400))
    return (-backDays...7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
  }

  // MARK: Now / next

  func nowPlaying(_ channel: Channel) -> Schedule? { nowByChannel[channel.id] }
  func upNext(_ channel: Channel) -> Schedule? { nextByChannel[channel.id] }

  /// Recomputes derived shelves. Cheap enough to run on every clock tick; publishes only when
  /// the result actually changed so views keep their identity, scroll and focus.
  func recomputeShelves(force: Bool = false) {
    let now = clock.nowMs
    guard force || now != lastShelfNow else { return }
    lastShelfNow = now

    let today = epg[clock.dayStart] ?? [:]
    let yesterday = epg[Calendar.current.date(byAdding: .day, value: -1, to: clock.dayStart) ?? clock.dayStart] ?? [:]
    var onNow: [OnNowItem] = []
    var upNext: [ProgramItem] = []
    var catchUp: [ProgramItem] = []
    var nowMap: [Int: Schedule] = [:]
    var nextMap: [Int: Schedule] = [:]

    for channel in channels {
      let list = today[channel.id] ?? []
      var current = list.first { $0.isAiring(at: now) }
      if current == nil, let spill = yesterday[channel.id]?.last, spill.isAiring(at: now) {
        current = spill
      }
      if let current { nowMap[channel.id] = current }
      onNow.append(OnNowItem(channel: channel, schedule: current))

      if let next = list.first(where: { $0.startTime > now }) {
        nextMap[channel.id] = next
        if next.startTime - now <= 3 * 3_600_000 {
          upNext.append(ProgramItem(channel: channel, schedule: next))
        }
      }
      if channel.canCatchUp,
         let ended = list.last(where: { $0.endTime <= now }),
         now - ended.endTime <= 6 * 3_600_000,
         ended.durationMinutes >= 10 {
        catchUp.append(ProgramItem(channel: channel, schedule: ended))
      }
    }
    upNext.sort { $0.schedule.startTime < $1.schedule.startTime }
    catchUp.sort { $0.schedule.endTime > $1.schedule.endTime }

    let fresh = Shelves(onNow: onNow, upNext: Array(upNext.prefix(40)), catchUp: Array(catchUp.prefix(40)))
    nowByChannel = nowMap
    nextByChannel = nextMap
    if fresh != shelves { shelves = fresh }
  }

  // MARK: Search

  func search(_ raw: String) -> SearchResults {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else { return SearchResults() }
    let now = clock.nowMs
    var results = SearchResults()

    results.channels = channels.filter {
      $0.name.localizedStandardContains(query) || $0.shortName.localizedStandardContains(query)
    }

    var seen = Set<Int>()
    for (_, dayMap) in epg.sorted(by: { $0.key < $1.key }) {
      for (channelID, list) in dayMap {
        guard let channel = channelsByID[channelID] else { continue }
        for programme in list where seen.insert(programme.id).inserted {
          let matches = programme.title.localizedStandardContains(query)
            || (programme.originalTitle?.localizedStandardContains(query) ?? false)
          guard matches else { continue }
          let item = ProgramItem(channel: channel, schedule: programme)
          if programme.isAiring(at: now) {
            results.onNow.append(item)
          } else if programme.isUpcoming(at: now) {
            results.upcoming.append(item)
          } else if channel.isWithinCatchUpWindow(programme, nowMs: now) {
            results.catchUp.append(item)
          }
        }
      }
    }
    results.upcoming.sort { $0.schedule.startTime < $1.schedule.startTime }
    results.catchUp.sort { $0.schedule.startTime > $1.schedule.startTime }
    results.onNow = Array(results.onNow.prefix(24))
    results.upcoming = Array(results.upcoming.prefix(36))
    results.catchUp = Array(results.catchUp.prefix(36))
    return results
  }

  // MARK: Freshness

  private func handleDayChange(_ day: Date) {
    let cutoff = Calendar.current.date(byAdding: .day, value: -Self.keptDays, to: day) ?? day
    for key in epg.keys where key < cutoff {
      epg.removeValue(forKey: key)
      loadedChunks = loadedChunks.filter { $0.day != key }
    }
    Task {
      await ensureEPG(day: day, for: channels)
      recomputeShelves(force: true)
    }
  }

  func refreshIfStale() async {
    if let last = lastChannelsRefresh, Date().timeIntervalSince(last) > 3_600 {
      await loadChannels(silently: true)
    } else if channels.isEmpty {
      await loadChannels()
    }
    await ensureEPG(day: clock.dayStart, for: channels)
    recomputeShelves(force: true)
  }
}
