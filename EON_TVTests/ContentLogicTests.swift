import XCTest
import EONKit
@testable import EON_TV

final class ContentLogicTests: XCTestCase {
  private func makeChannel(id: Int = 1, cutv: Bool = true, cutvDelay: Int = 7, startOver: Bool = true) -> Channel {
    Channel(
      id: id, name: "Test", shortName: "T",
      logos: ["LOGO_16_9_DARK": [ImageRendition(path: "/logo", height: 270)]],
      baseURL: "example.test",
      publishingPoint: [PublishingPoint(publishingPoint: "pp", audioLanguage: "eng", subtitleLanguage: "eng", profileIds: [1], playerCfgs: [PlayerConfig(id: 1, type: "live", sig: "a"), PlayerConfig(id: 2, type: "cutv", sig: "b")])],
      subscribed: true, drmRequired: false, castEnabled: true, liveEnabled: true, cutvEnabled: cutv,
      drEnabled: true, aaEnabled: false, startOverEnabled: startOver, cutvDelay: cutvDelay
    )
  }

  private func makeSchedule(id: Int = 10, channel: Int = 1, start: Int, end: Int) -> Schedule {
    Schedule(id: id, title: "Programme", originalTitle: nil, shortDescription: nil, channelId: channel,
             startTime: start, endTime: end, seasonNumber: nil, episodeNumber: nil, live: false, images: [], baseURL: "example.test")
  }

  func testScheduleProgressAndState() {
    let schedule = makeSchedule(start: 1_000_000, end: 1_600_000)
    XCTAssertEqual(schedule.progress(at: 1_300_000), 0.5, accuracy: 0.001)
    XCTAssertTrue(schedule.isAiring(at: 1_300_000))
    XCTAssertTrue(schedule.hasEnded(at: 1_600_000))
    XCTAssertTrue(schedule.isUpcoming(at: 999_999))
    XCTAssertEqual(schedule.progress(at: 0), 0)
    XCTAssertEqual(schedule.progress(at: 2_000_000), 1)
  }

  func testCatchUpWindowNormalisesUnits() {
    XCTAssertEqual(makeChannel(cutvDelay: 7).catchUpWindow, 7 * 86_400)
    XCTAssertEqual(makeChannel(cutvDelay: 168).catchUpWindow, 168 * 3_600)
    XCTAssertEqual(makeChannel(cutvDelay: 10_080).catchUpWindow, 10_080 * 60)
    XCTAssertEqual(makeChannel(cutvDelay: 604_800).catchUpWindow, 604_800)
    XCTAssertEqual(makeChannel(cutvDelay: 0).catchUpWindow, 7 * 86_400)
    XCTAssertEqual(makeChannel(cutv: false).catchUpWindow, 0)
  }

  func testCatchUpEligibilityRespectsWindowAndChannel() {
    let channel = makeChannel(cutvDelay: 1)
    let now = 10 * 86_400_000
    let recent = makeSchedule(start: now - 3_600_000, end: now - 1_800_000)
    let old = makeSchedule(id: 11, start: now - 2 * 86_400_000, end: now - 2 * 86_400_000 + 3_600_000)
    let future = makeSchedule(id: 12, start: now + 60_000, end: now + 120_000)
    XCTAssertTrue(channel.isWithinCatchUpWindow(recent, nowMs: now))
    XCTAssertFalse(channel.isWithinCatchUpWindow(old, nowMs: now))
    XCTAssertFalse(channel.isWithinCatchUpWindow(future, nowMs: now))
    XCTAssertFalse(makeChannel(cutv: false).isWithinCatchUpWindow(recent, nowMs: now))
    XCTAssertFalse(channel.canStartOver == false)
  }

  func testStoreDerivesShelvesFromDemoGuide() async {
    let clock = LiveClock()
    let store = ContentStore(backend: DemoBackend.make(), clock: clock)
    await store.loadInitial()

    XCTAssertFalse(store.channels.isEmpty)
    XCTAssertTrue(store.channels.contains(where: \.requiresParentalPin), "the demo line-up has an adult channel")
    XCTAssertEqual(store.shelves.onNow.count, store.channels.filter { !$0.requiresParentalPin }.count, "Home's shelves leave adult channels out")
    XCTAssertEqual(store.todayLoadedFraction, 1, accuracy: 0.001)

    let now = clock.nowMs
    for item in store.shelves.onNow {
      XCTAssertNotNil(item.schedule, "every demo channel airs something at any moment")
      XCTAssertTrue(item.schedule?.isAiring(at: now) ?? false)
    }
    let starts = store.shelves.upNext.map(\.schedule.startTime)
    XCTAssertEqual(starts, starts.sorted())
    XCTAssertTrue(store.shelves.upNext.allSatisfy { $0.schedule.startTime > now })
    XCTAssertTrue(store.shelves.catchUp.allSatisfy { $0.channel.canCatchUp && $0.schedule.hasEnded(at: now) })
    XCTAssertEqual(store.channelNumber(store.channels[0]), 1)
    XCTAssertEqual(store.chunkIndex(for: store.channels[ContentStore.chunkSize].id), 1)
  }

  func testSearchGroupsResults() async {
    let clock = LiveClock()
    let store = ContentStore(backend: DemoBackend.make(), clock: clock)
    await store.loadInitial()

    let channels = store.search("btv")
    XCTAssertTrue(channels.channels.contains { $0.name.localizedStandardContains("bTV") })
    XCTAssertTrue(store.search("x").isEmpty, "single characters are too broad to search")
    XCTAssertTrue(store.search("zzzz-no-such-programme").isEmpty)

    let programmes = store.search("Desk")
    let now = clock.nowMs
    XCTAssertTrue(programmes.onNow.allSatisfy { $0.schedule.isAiring(at: now) })
    XCTAssertTrue(programmes.upcoming.allSatisfy { $0.schedule.isUpcoming(at: now) })
    XCTAssertTrue(programmes.catchUp.allSatisfy { $0.channel.isWithinCatchUpWindow($0.schedule, nowMs: now) })
  }

  /// Skipping inside a past programme requests a fresh timeshift stream. Until that stream is
  /// anchored the controller must keep reporting the position the viewer asked for: falling
  /// back to the live edge made the current programme flash in and turned the next skip into a
  /// jump to live.
  func testSeekKeepsRequestedPositionWhileTimeshiftStreamLoads() async {
    let clock = LiveClock()
    let store = ContentStore(backend: DemoBackend.make(), clock: clock)
    await store.loadInitial()
    guard let item = store.shelves.catchUp.first else { return XCTFail("demo guide offers no catch-up") }
    let history = WatchHistory()
    let controller = PlayerController(
      request: PlaybackRequest(channel: item.channel, mode: .catchUp(item.schedule, offsetMs: 0), lineup: store.channels),
      backend: DemoBackend.make(), store: store, history: history, favorites: FavoritesStore(), gate: ParentalGate(), clock: clock
    )
    defer { controller.stop(); history.clear() }

    let target = item.schedule.startTime + 60_000
    controller.seek(toWallClockMs: target)
    XCTAssertFalse(controller.isLive)
    XCTAssertEqual(controller.playheadMs, target, "the playhead is where the stream was requested, not the live edge")
    XCTAssertEqual(controller.currentProgram?.id, item.schedule.id)
    XCTAssertEqual(controller.phase, .loading(obscuresVideo: true), "a first load has no picture to keep")

    // A further skip while the first stream is still loading builds on the requested position.
    let next = (controller.playheadMs ?? 0) + 15_000
    controller.seek(toWallClockMs: next)
    XCTAssertFalse(controller.isLive, "a skip made mid-load must not fall through to live")
    XCTAssertEqual(controller.playheadMs, next)
    XCTAssertEqual(controller.currentProgram?.id, item.schedule.id)

    controller.load(channel: item.channel, mode: .live)
    XCTAssertTrue(controller.isLive)
    XCTAssertNil(controller.playheadMs, "while a live stream loads, the live edge is the position")
    XCTAssertEqual(controller.currentProgram?.id, store.nowPlaying(item.channel)?.id)
  }

  func testHistoryResumeRules() {
    let history = WatchHistory()
    history.clear()
    let schedule = makeSchedule(id: 555, start: 0, end: 1_000_000)
    history.updateResume(for: schedule, positionMs: 500_000)
    XCTAssertEqual(history.resumePosition(for: 555), 500_000)
    history.updateResume(for: schedule, positionMs: 990_000)
    XCTAssertNil(history.resumePosition(for: 555), "almost finished programmes are not offered for resume")
    history.recordChannel(1); history.recordChannel(2); history.recordChannel(1)
    XCTAssertEqual(history.recentChannelIDs, [1, 2])
    history.clear()
  }

  // MARK: Favourites, PIN and profiles

  /// Polls until `condition` holds, for state that settles after a background save.
  private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  func testFavoritesFollowThePlatformList() async throws {
    let repository = DemoFavoritesRepository(profiles: DemoProfilesRepository())
    let favorites = FavoritesStore()
    await favorites.attach(repository)
    XCTAssertEqual(favorites.ids, [103, 115])

    favorites.toggle(makeChannel(id: 104))
    XCTAssertTrue(favorites.contains(104), "a toggle shows at once")
    try await Task.sleep(for: .milliseconds(500))
    let saved = try await repository.getFavorites().channelIDs
    XCTAssertEqual(saved, [103, 115, 104])

    favorites.removeAll()
    XCTAssertTrue(favorites.isEmpty)
    try await Task.sleep(for: .milliseconds(500))
    let cleared = try await repository.getFavorites().channelIDs
    XCTAssertEqual(cleared, [])
  }

  func testFavoritesRollBackWhenTheSaveFails() async {
    final class FailingFavorites: FavoritesRepository {
      func getFavorites() async throws -> FavoriteList { FavoriteList(id: 1, name: "Favorites", channelIDs: [7]) }
      func update(list: FavoriteList.ID, adding: [Int], removing: [Int]) async throws { throw URLError(.notConnectedToInternet) }
    }
    let favorites = FavoritesStore()
    await favorites.attach(FailingFavorites())
    favorites.toggle(makeChannel(id: 8))
    XCTAssertTrue(favorites.contains(8))
    await waitUntil { favorites.lastError != nil }
    XCTAssertFalse(favorites.contains(8), "the platform refused, so the toggle is undone")
    XCTAssertEqual(favorites.ids, [7])
    XCTAssertNotNil(favorites.lastError)
  }

  func testParentalGateUnlocksWithTheHouseholdPin() async {
    let gate = ParentalGate()
    gate.attach(DemoParentalControlRepository())
    let adult = Channel(
      id: 5, name: "Adult", shortName: "A", logos: [:], publishingPoint: [],
      subscribed: true, drmRequired: false, castEnabled: false, liveEnabled: true, cutvEnabled: false,
      drEnabled: false, aaEnabled: false, startOverEnabled: false, cutvDelay: 0, ageRating: "18"
    )
    XCTAssertTrue(gate.needsPin(for: adult))
    XCTAssertFalse(gate.needsPin(for: makeChannel()))

    let wrong = await gate.unlock(with: "1234")
    XCTAssertEqual(wrong, .wrongPin)
    XCTAssertTrue(gate.needsPin(for: adult))

    let right = await gate.unlock(with: DemoParentalControlRepository.pin)
    XCTAssertEqual(right, .unlocked)
    XCTAssertFalse(gate.needsPin(for: adult))

    gate.lock()
    XCTAssertTrue(gate.needsPin(for: adult))
  }

  /// Nothing of an adult channel is requested before the PIN, and cancelling the PIN after a
  /// channel switch goes back to what was playing.
  func testPlayerWaitsForThePinBeforeStreamingAnAdultChannel() async throws {
    let clock = LiveClock()
    let backend = DemoBackend.make()
    let store = ContentStore(backend: backend, clock: clock)
    await store.loadInitial()
    let adult = try XCTUnwrap(store.channels.first(where: \.requiresParentalPin))
    let regular = try XCTUnwrap(store.channels.first { !$0.requiresParentalPin })
    let gate = ParentalGate()
    gate.attach(backend.parental)
    let history = WatchHistory()
    history.use(profileID: -1)

    let controller = PlayerController(
      request: PlaybackRequest(channel: regular, mode: .live, lineup: store.channels),
      backend: backend, store: store, history: history, favorites: FavoritesStore(), gate: gate, clock: clock
    )
    defer { controller.stop(); history.clear() }
    controller.start()
    XCTAssertTrue(controller.phase.isLoading)

    controller.switchChannel(adult)
    XCTAssertEqual(controller.phase, .needsPin)
    XCTAssertEqual(controller.channel, adult)
    XCTAssertNil(controller.player.currentItem, "the locked channel's stream is never requested")

    XCTAssertTrue(controller.cancelUnlock())
    XCTAssertEqual(controller.channel, regular)

    controller.switchChannel(adult)
    let wrong = await controller.unlock(with: "9999")
    XCTAssertEqual(wrong, .wrongPin)
    XCTAssertEqual(controller.phase, .needsPin)
    let right = await controller.unlock(with: DemoParentalControlRepository.pin)
    XCTAssertEqual(right, .unlocked)
    XCTAssertTrue(controller.phase.isLoading)
    XCTAssertFalse(controller.cancelUnlock(), "once unlocked there is nothing to cancel back to")
  }

  func testProfilesLimitTheLineUpToTheirMaturity() async throws {
    let clock = LiveClock()
    let backend = DemoBackend.make()
    let profiles = try await backend.profiles.getProfiles()
    let kids = try XCTUnwrap(profiles.first { $0.name == "Kids" })

    let store = ContentStore(backend: backend, clock: clock, profile: kids)
    await store.loadChannels()
    XCTAssertFalse(store.channels.isEmpty)
    XCTAssertTrue(store.channels.allSatisfy { kids.allows(ageRating: $0.ageRating) })
    XCTAssertFalse(store.categories.contains { $0.name == "Movies" || $0.name == "Adult" }, "categories left empty disappear")

    let family = ContentStore(backend: backend, clock: clock, profile: profiles.first { $0.isDefault })
    await family.loadChannels()
    XCTAssertGreaterThan(family.channels.count, store.channels.count)
  }

  func testHistoryIsKeptPerProfile() {
    let history = WatchHistory()
    history.use(profileID: -101)
    history.clear()
    history.recordChannel(42)
    history.use(profileID: -102)
    XCTAssertEqual(history.recentChannelIDs, [], "another profile starts with its own history")
    history.recordChannel(7)
    history.use(profileID: -101)
    XCTAssertEqual(history.recentChannelIDs, [42])
    history.clear()
    history.use(profileID: -102)
    history.clear()
  }

  func testProtectedProfilesNeedTheirPinToSwitch() async throws {
    let repository = DemoProfilesRepository()
    let store = ProfileStore()
    try await store.load(from: repository)
    let kids = try XCTUnwrap(store.profiles.first { $0.pinProtected })

    do {
      try await store.activate(kids, pin: "9999", using: repository)
      XCTFail("a wrong PIN must not switch profile")
    } catch AuthError.wrongPin {}
    XCTAssertNotEqual(store.activeID, kids.id)

    try await store.activate(kids, pin: DemoParentalControlRepository.pin, using: repository)
    XCTAssertEqual(store.activeID, kids.id)
  }
}
