import XCTest
@testable import EON_TV

/// The guide builds cells only near the viewport. These pin down which hours of the day a scroll
/// offset maps to and which programmes a row builds for them.
final class GuideLayoutTests: XCTestCase {
  private let metrics = GuideMetrics()
  private let hour = GuideMetrics.hourMs
  /// A 1080p viewport minus the channel column, at the default text size: about 2.56 hours.
  private let viewport: CGFloat = 1_640

  private func schedule(id: Int, start: Int, end: Int) -> Schedule {
    Schedule(id: id, title: "Programme \(id)", originalTitle: nil, shortDescription: nil, channelId: 1,
             startTime: start, endTime: end, seasonNumber: nil, episodeNumber: nil, live: false, images: [], baseURL: nil)
  }

  // MARK: Window

  func testWindowCoversTheViewportPlusAnHourEachSideInWholeHours() {
    // Scrolled to 10:00: the viewport shows 10:00–12:34, so 09:00–14:00 is built.
    let window = metrics.buildWindow(offsetX: metrics.hourWidth * 10, viewportWidth: viewport)
    XCTAssertEqual(window, 9 * hour..<14 * hour)
  }

  func testWindowStaysPutWhileScrollingWithinAnHour() {
    let a = metrics.buildWindow(offsetX: metrics.hourWidth * 10, viewportWidth: viewport)
    let b = metrics.buildWindow(offsetX: metrics.hourWidth * 10.4, viewportWidth: viewport)
    XCTAssertEqual(a, b)
    let c = metrics.buildWindow(offsetX: metrics.hourWidth * 11, viewportWidth: viewport)
    XCTAssertEqual(c, 10 * hour..<15 * hour)
  }

  func testWindowIsClampedToTheDay() {
    XCTAssertEqual(metrics.buildWindow(offsetX: 0, viewportWidth: viewport), 0..<4 * hour)
    let end = metrics.buildWindow(offsetX: metrics.dayWidth - viewport, viewportWidth: viewport)
    XCTAssertEqual(end, 20 * hour..<GuideMetrics.dayMs)
  }

  func testWindowScalesWithText() {
    // Larger text widens an hour, so the same viewport shows fewer hours.
    let large = GuideMetrics(scale: 1.6)
    let window = large.buildWindow(offsetX: large.hourWidth * 10, viewportWidth: viewport)
    XCTAssertEqual(window, 9 * hour..<13 * hour)
  }

  // MARK: Programmes built for a window

  func testRowBuildsOverlappingProgrammesAndOneNeighbourEachSide() {
    let list = (0..<6).map { schedule(id: $0, start: (8 + $0) * hour, end: (9 + $0) * hour) }
    // 10:00–12:00 overlaps the third and fourth programmes; their neighbours come along.
    XCTAssertEqual(list.guideRange(dayStartMs: 0, window: 10 * hour..<12 * hour), 1..<5)
    // At either end of the list the missing neighbour is simply left out.
    XCTAssertEqual(list.guideRange(dayStartMs: 0, window: 0..<9 * hour), 0..<2)
    XCTAssertEqual(list.guideRange(dayStartMs: 0, window: 13 * hour..<24 * hour), 4..<6)
  }

  func testRowBuildsNothingWhenNoProgrammeTouchesTheWindow() {
    let list = (0..<6).map { schedule(id: $0, start: (8 + $0) * hour, end: (9 + $0) * hour) }
    XCTAssertNil(list.guideRange(dayStartMs: 0, window: 0..<6 * hour))
    XCTAssertNil([Schedule]().guideRange(dayStartMs: 0, window: 0..<24 * hour))
  }

  func testTheProgrammeAfterALongFilmIsBuiltSoFocusCanReachIt() {
    let list = [
      schedule(id: 1, start: 9 * hour, end: 10 * hour),
      schedule(id: 2, start: 10 * hour, end: 13 * hour),
      schedule(id: 3, start: 13 * hour, end: 14 * hour),
    ]
    // The film starts inside 09:00–11:00; what follows it begins two hours past the window.
    XCTAssertEqual(list.guideRange(dayStartMs: 0, window: 9 * hour..<11 * hour), 0..<3)
  }

  func testWindowIsRelativeToTheDayStart() {
    let dayStart = 1_758_499_200_000 // an arbitrary midnight in epoch milliseconds
    let list = [
      schedule(id: 1, start: dayStart + 9 * hour, end: dayStart + 10 * hour),
      schedule(id: 2, start: dayStart + 10 * hour, end: dayStart + 11 * hour),
      schedule(id: 3, start: dayStart + 11 * hour, end: dayStart + 12 * hour),
    ]
    XCTAssertEqual(list.guideRange(dayStartMs: dayStart, window: 10 * hour..<11 * hour), 0..<3)
    XCTAssertEqual(list.guideRange(dayStartMs: dayStart, window: 11 * hour..<12 * hour), 1..<3)
  }
}
