#if DEBUG
import Foundation
import UIKit

/// A fixture-backed `Backend` used only in debug builds so the interface, focus behaviour and
/// player can be exercised in the simulator without a subscriber account. It conforms to the
/// SDK's repository protocols so the rest of the app is unaware of the difference.
enum DemoBackend {
  static let baseURL = "demo.local"

  static func make() -> Backend {
    let fixtures = DemoFixtures()
    return Backend(
      auth: DemoAuthRepository(),
      channels: DemoChannelsRepository(fixtures: fixtures),
      epg: DemoEpgRepository(fixtures: fixtures),
      streaming: DemoStreamingRepository(),
      syncClock: {},
      hasStoredSession: { true },
      clearSession: {},
      isDemo: true
    )
  }
}

// MARK: - Repositories

final class DemoAuthRepository: AuthRepository {
  private let household = Household(id: 1, contractNumber: "DEMO-000-001", buyerId: "demo", packageName: "EON Premium (Demo)")
  private let device = Device(deviceId: 1, deviceNumber: "demo-device", friendlyId: "atv-demo-001")
  private var codeAttempts = 0

  func login(username: String, password: String) async throws -> Household {
    try? await Task.sleep(for: .milliseconds(600))
    return household
  }
  func requestOneTimeCode() async throws -> OneTimeCode {
    try? await Task.sleep(for: .milliseconds(600))
    codeAttempts = 0
    return OneTimeCode(otp: "DEMO42", expiresInSeconds: 600)
  }
  /// "Confirmed" on the second poll so the waiting state is visible for a moment.
  func login(oneTimeCode: OneTimeCode) async throws -> Household {
    codeAttempts += 1
    guard codeAttempts >= 2 else { throw AuthError.codeNotConfirmed }
    return household
  }
  func getHousehold() async throws -> Household { household }
  func registeredDevice() async -> Device? { device }
}

final class DemoChannelsRepository: ChannelsRepository {
  let fixtures: DemoFixtures
  init(fixtures: DemoFixtures) { self.fixtures = fixtures }
  func getChannels() async throws -> [Channel] { fixtures.channels }
  func getCategories() async throws -> [ChannelCategory] {
    try? await Task.sleep(for: .milliseconds(350))
    return fixtures.categories
  }
}

final class DemoEpgRepository: EpgRepository {
  let fixtures: DemoFixtures
  init(fixtures: DemoFixtures) { self.fixtures = fixtures }
  func getSchedule(forChannel channel: Channel) async throws -> [Schedule] {
    try await getSchedule(forChannel: channel, forDay: Date())
  }
  func getSchedule(forChannel channel: Channel, forDay day: Date) async throws -> [Schedule] {
    try? await Task.sleep(for: .milliseconds(250))
    return fixtures.schedules(for: channel.id, day: day)
  }
  func getSchedule(forChannels channels: [Channel]) async throws -> [Int: [Schedule]] {
    try await getSchedule(forChannels: channels, forDay: Date())
  }
  func getSchedule(forChannels channels: [Channel], forDay day: Date) async throws -> [Int: [Schedule]] {
    try? await Task.sleep(for: .milliseconds(Int.random(in: 300...900)))
    return Dictionary(uniqueKeysWithValues: channels.map { ($0.id, fixtures.schedules(for: $0.id, day: day)) })
  }
}

final class DemoStreamingRepository: StreamingRepository {
  /// Public test streams stand in for the platform's protected streams: a live stream for the
  /// live edge, and Apple's sample with alternate audio and subtitles for catch-up modes.
  private let live = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!
  private let timeshift = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!

  func getStreamingUrl(forChannel: Channel, startTime: Int?) async throws -> (URL, Int, Int) {
    try? await Task.sleep(for: .milliseconds(500))
    let now = ServerTime.shared.currentTimeMillis()
    return (startTime == nil ? live : timeshift, startTime ?? now, now)
  }
}

// MARK: - Fixtures

/// Deterministic channel line-up and programme data.
final class DemoFixtures {
  let channels: [Channel]
  let categories: [ChannelCategory]
  private var cache: [String: [Schedule]] = [:]

  private struct Genre {
    let name: String
    let channels: [(String, String)]
    let titles: [String]
    let durations: [Int]
  }

  private static let genres: [Genre] = [
    Genre(name: "News", channels: [("bTV News", "bTV N"), ("Nova News", "NOVA N"), ("BNT 1", "BNT1"), ("Euronews", "EURO"), ("CNN International", "CNN"), ("BBC World News", "BBC")],
          titles: ["Morning Briefing", "World Today", "Business Hour", "The Debate", "Weather & Traffic", "Evening News", "Late Edition", "Politics Live", "Global Markets", "Sports Desk"],
          durations: [30, 30, 60, 45, 15, 60, 30]),
    Genre(name: "Sports", channels: [("Eurosport 1", "ES1"), ("Eurosport 2", "ES2"), ("Diema Sport", "DIEMA S"), ("MAX Sport 1", "MAX1"), ("Nova Sport", "NOVA S"), ("Ring", "RING")],
          titles: ["Champions League Magazine", "Grand Slam Tennis", "Cycling: Vuelta Stage 12", "Premier League: Matchday", "Snooker Masters", "Motorsport Weekend", "Athletics Diamond League", "Basketball Euroleague", "Boxing Night", "Sports Center"],
          durations: [60, 90, 120, 150, 45, 60]),
    Genre(name: "Movies", channels: [("HBO", "HBO"), ("Cinemax", "CMAX"), ("Kino Nova", "KINO"), ("Fox Movies", "FOXM"), ("AMC", "AMC"), ("Film+", "FILM+")],
          titles: ["The Last Signal", "Northern Lights", "Midnight in Sofia", "Paper Kingdom", "Quiet Harbor", "Iron Horizon", "The Cartographer", "Blue Monday", "A Winter Guest", "Hollow Road"],
          durations: [95, 110, 120, 135, 90, 105]),
    Genre(name: "Kids", channels: [("Nickelodeon", "NICK"), ("Cartoon Network", "CN"), ("Disney Channel", "DISNEY"), ("Boomerang", "BOOM")],
          titles: ["Rocket Pals", "Puzzle Forest", "Captain Whiskers", "Dino Camp", "The Tiny Explorers", "Sky Racers", "Robot School", "Magic Bakery"],
          durations: [15, 20, 25, 30, 45]),
    Genre(name: "Documentary", channels: [("National Geographic", "NATGEO"), ("Discovery", "DISC"), ("History", "HIST"), ("Viasat Nature", "NATURE"), ("Travel", "TRAVEL")],
          titles: ["Planet Rivers", "Engineering Giants", "Lost Cities", "Wild Balkans", "Deep Ocean", "The Space Race", "Ancient Builders", "Volcano Watch", "Food Routes", "Arctic Frontier"],
          durations: [45, 50, 60, 90]),
    Genre(name: "Music", channels: [("MTV", "MTV"), ("The Voice", "VOICE"), ("Magic TV", "MAGIC")],
          titles: ["Top 20 Countdown", "Live Sessions", "Fresh Hits", "Retro Hour", "Club Night", "Unplugged", "Chart Show"],
          durations: [30, 60, 60, 120]),
    Genre(name: "Entertainment", channels: [("bTV", "bTV"), ("Nova TV", "NOVA"), ("bTV Comedy", "COMEDY"), ("Fox", "FOX"), ("TLC", "TLC"), ("Star Channel", "STAR")],
          titles: ["The Morning Show", "Cooking Duel", "Family Ties", "The Big Quiz", "Hidden Talents", "Neighbours", "Late Night Live", "Home Makeover", "Comedy Club", "Mystery Hour"],
          durations: [30, 45, 60, 60, 90]),
  ]

  init() {
    var all: [Channel] = []
    var cats: [ChannelCategory] = []
    var nextID = 101
    for (genreIndex, genre) in Self.genres.enumerated() {
      var members: [Channel] = []
      for (name, short) in genre.channels {
        let id = nextID
        nextID += 1
        let canCatchUp = (id % 5) != 0
        let channel = Channel(
          id: id,
          name: name,
          shortName: short,
          images: [ChannelImage(path: "/logo/\(id)?t=\(short.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? short)", width: 480, height: 270, size: "XL", type: "LOGO")],
          baseURL: DemoBackend.baseURL,
          publishingPoint: [PublishingPoint(publishingPoint: "demo-\(id)", audioLanguage: "eng", subtitleLanguage: "eng", profileIds: [1], playerCfgs: [PlayerConfig(id: 1, type: "live", sig: "demo"), PlayerConfig(id: 2, type: "cutv", sig: "demo")])],
          subscribed: true,
          drmRequired: false,
          castEnabled: true,
          liveEnabled: true,
          cutvEnabled: canCatchUp,
          drEnabled: true,
          aaEnabled: false,
          startOverEnabled: canCatchUp,
          cutvDelay: 7
        )
        members.append(channel)
        all.append(channel)
      }
      cats.append(ChannelCategory(id: 10 + genreIndex, name: genre.name, defaultList: false, channels: members))
    }
    channels = all
    categories = [ChannelCategory(id: 1, name: "All Channels", defaultList: true, channels: all)] + cats
  }

  func schedules(for channelID: Int, day: Date) -> [Schedule] {
    let dayStart = day.startOfTheDay
    let key = "\(channelID)-\(Int(dayStart.timeIntervalSince1970))"
    if let cached = cache[key] { return cached }

    guard let channel = channels.first(where: { $0.id == channelID }),
          let genre = Self.genres.first(where: { $0.channels.contains { $0.0 == channel.name } })
    else { return [] }

    var rng = SeededGenerator(seed: UInt64(channelID) &* 7919 &+ UInt64(Int(dayStart.timeIntervalSince1970) / 86_400))
    var result: [Schedule] = []
    var cursor = dayStart.timestamp
    let dayEnd = dayStart.endOfTheDay.timestamp + 1
    var index = 0
    while cursor < dayEnd {
      let durationMs = genre.durations[Int(rng.next() % UInt64(genre.durations.count))] * 60_000
      let title = genre.titles[Int(rng.next() % UInt64(genre.titles.count))]
      let hasEpisode = rng.next() % 3 == 0
      let id = channelID * 1_000_000 + (Int(dayStart.timeIntervalSince1970) / 86_400 % 1000) * 100 + index
      let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
      result.append(
        Schedule(
          id: id,
          title: title,
          originalTitle: nil,
          shortDescription: Self.descriptions[Int(rng.next() % UInt64(Self.descriptions.count))],
          channelId: channelID,
          startTime: cursor,
          endTime: cursor + durationMs,
          seasonNumber: hasEpisode ? Int(rng.next() % 6 + 1) : nil,
          episodeNumber: hasEpisode ? Int(rng.next() % 20 + 1) : nil,
          live: false,
          images: [ChannelImage(path: "/poster/\(id)?t=\(encoded)", width: 480, height: 270, size: "XL", type: "EVENT_16_9")],
          baseURL: DemoBackend.baseURL
        )
      )
      cursor += durationMs
      index += 1
    }
    cache[key] = result
    return result
  }

  private static let descriptions = [
    "An in-depth look at the stories shaping the day, with analysis from correspondents around the world.",
    "The best moments, expert commentary and everything you need before the next big match.",
    "A gripping story of family, ambition and second chances set against a changing city.",
    "Join the crew as they explore, build and solve puzzles in a world full of surprises.",
    "Stunning photography reveals the hidden lives of creatures in one of Europe's last wild places.",
    "A fresh mix of the week's biggest tracks, live performances and exclusive interviews.",
    "Laughter, rivalry and heart as contestants face the toughest challenge of the season.",
  ]
}

/// Small deterministic generator so fixtures are stable between launches.
struct SeededGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
  mutating func next() -> UInt64 {
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state
  }
}

// MARK: - Artwork

/// Renders placeholder artwork for `demo.local` image URLs: gradient posters with the programme
/// title and clean wordmark-style channel logos.
enum DemoArtwork {
  nonisolated static func render(_ url: URL) -> UIImage {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let title = components?.queryItems?.first { $0.name == "t" }?.value ?? ""
    let isLogo = url.path.hasPrefix("/logo/")
    let seed = url.path.unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }

    let size = CGSize(width: 480, height: 270)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      let cg = context.cgContext
      if isLogo {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: title.count > 5 ? 64 : 84, weight: .heavy),
          .foregroundColor: UIColor.white,
          .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let height = text.size().height
        text.draw(in: CGRect(x: 16, y: (size.height - height) / 2, width: size.width - 32, height: height))
        return
      }
      drawAurora(in: cg, size: size, seed: Int(seed % 9973))
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 34, weight: .bold),
        .foregroundColor: UIColor.white.withAlphaComponent(0.92),
      ]
      let text = NSAttributedString(string: title, attributes: attributes)
      text.draw(in: CGRect(x: 28, y: size.height - 28 - 44, width: size.width - 56, height: 44))
    }
  }

  /// The aurora as a poster: two glowing wave bands with bright ridges on a near-black field,
  /// the CoreGraphics twin of `AuroraWaves`.
  nonisolated static func drawAurora(in cg: CGContext, size: CGSize, seed: Int) {
    let palette = AuroraGeometry.palette(seed: seed)
    let accent = AuroraGeometry.palette(seed: seed + 1)
    let variant = CGFloat(seed % 13) / 13
    let rect = CGRect(origin: .zero, size: size)
    cg.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.05, alpha: 1))
    cg.fill(rect)

    let wide = rect.insetBy(dx: -size.width * 0.15, dy: 0)
    let bands: [(AuroraGeometry.Palette, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (palette, 0.48 + variant * 0.1, 0.13, 1.0, variant, 0.45),
      (accent, 0.60 - variant * 0.1, 0.10, 0.75, variant + 0.4, 0.35),
    ]
    for (colors, baseline, amplitude, frequency, phase, thickness) in bands {
      cg.saveGState()
      cg.setShadow(offset: .zero, blur: size.height * 0.16, color: colors.mid.cgColor(alpha: 0.9))
      cg.addPath(AuroraGeometry.band(in: wide, baseline: baseline, amplitude: amplitude, frequency: frequency, phase: phase, thickness: thickness))
      cg.setFillColor(colors.deep.cgColor(alpha: 0.9))
      cg.fillPath()
      cg.restoreGState()

      cg.saveGState()
      cg.setShadow(offset: .zero, blur: size.height * 0.05, color: colors.core.cgColor(alpha: 1))
      cg.addPath(AuroraGeometry.ridge(in: wide, baseline: baseline, amplitude: amplitude, frequency: frequency, phase: phase))
      cg.setStrokeColor(colors.core.cgColor(alpha: 0.9))
      cg.setLineWidth(size.height * 0.012)
      cg.setLineCap(.round)
      cg.strokePath()
      cg.restoreGState()
    }
  }
}
#endif
