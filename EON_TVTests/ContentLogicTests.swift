import XCTest
import EONKit
@testable import EON_TV

final class ContentLogicTests: XCTestCase {
  private func makeChannel(id: Int = 1, cutv: Bool = true, cutvDelay: Int = 7, startOver: Bool = true) -> Channel {
    Channel(
      id: id, name: "Test", shortName: "T",
      images: [ChannelImage(path: "/logo", width: 480, height: 270, size: "XL", type: "LOGO")],
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
    XCTAssertEqual(store.shelves.onNow.count, store.channels.count)
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
      backend: DemoBackend.make(), store: store, history: history, favorites: FavoritesStore(), clock: clock
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

  func testFavoritesToggleAndHistoryResumeRules() {
    let favorites = FavoritesStore()
    let channel = makeChannel(id: 987_654)
    let initiallyContained = favorites.contains(channel.id)
    favorites.toggle(channel)
    XCTAssertEqual(favorites.contains(channel.id), !initiallyContained)
    favorites.toggle(channel)
    XCTAssertEqual(favorites.contains(channel.id), initiallyContained)

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
}
