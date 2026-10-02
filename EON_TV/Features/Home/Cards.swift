import SwiftUI
import EONKit

/// Programme + channel card used on every shelf, in the shape of the system TV app's episode
/// cards. The artwork fills the card and carries only what belongs on a picture: the channel
/// logo, the live badge or start time, and an airing programme's progress. The words sit
/// beneath it on the canvas — a small kicker naming the channel, the title and a line of facts,
/// with the description where a shelf has room for it. On focus the artwork lifts behind a thin
/// bright rim with a shadow and the teal halo, and the caption settles onto a glass panel. The
/// card is the label of a `.bare` button, so only the artwork lifts, never the caption.
///
/// The card follows the viewer's text size: it grows with the caption (up to a cap) so a title
/// keeps about the same number of characters, and at accessibility sizes the title may take a
/// second line rather than truncate.
struct ProgramCard: View {
  let channel: Channel
  let schedule: Schedule?
  var width: CGFloat = Theme.programCardWidth
  var resumeFraction: Double? = nil
  var showsChannelName = true
  var showsDescription = false
  /// Fades the artwork and caption for a programme that can't be played yet. Fading a whole
  /// card with `opacity` would flatten its glass and ghost the badges, so the image and the
  /// words fade separately.
  var isDimmed = false

  @Environment(LiveClock.self) private var clock
  @Environment(\.isFocused) private var isFocused
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .caption) private var textScale: CGFloat = 1

  private var scaledWidth: CGFloat { width * min(textScale, Theme.maxArtworkScale) }
  private var height: CGFloat { scaledWidth * 9 / 16 }
  private var textOpacity: Double { isDimmed ? 0.55 : 1 }

  var body: some View {
    let now = clock.nowMs
    VStack(alignment: .leading, spacing: 14) {
      artwork(now: now)
        .frame(width: scaledWidth, height: height)
        .cardChrome(isFocused: isFocused)

      CardCaption {
        caption(now: now)
      }
      .offset(y: isFocused ? 10 : 0)
    }
    .frame(width: scaledWidth)
    .animation(Theme.focusAnimation, value: isFocused)
  }

  private func progress(now: Int) -> Double? {
    if let resumeFraction { return resumeFraction }
    if let schedule, schedule.isAiring(at: now) { return schedule.progress(at: now) }
    return nil
  }

  private func artwork(now: Int) -> some View {
    ZStack(alignment: .top) {
      RemoteImage(url: schedule?.posterURL) {
        ZStack {
          ArtworkPlaceholder(seed: channel.id)
          ChannelLogo(channel: channel, height: height * 0.28, platter: false)
        }
      }
      .frame(width: scaledWidth, height: height)
      .opacity(isDimmed ? 0.45 : 1)

      // A little shade behind the pills at the top and the progress line at the foot, so both
      // read on bright artwork.
      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.5), location: 0),
          .init(color: .clear, location: 0.4),
          .init(color: .clear, location: 0.65),
          .init(color: .black.opacity(0.55), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      // The logo platter and the badge are the artwork's two pieces of glass; one container
      // renders both in a single pass.
      GlassEffectContainer {
        HStack(alignment: .top) {
          ChannelLogo(channel: channel, height: 30)
          Spacer()
          statusBadge(now: now)
        }
        .padding(16)
      }
    }
    .overlay(alignment: .bottom) {
      if let progress = progress(now: now) {
        ProgressBar(progress: progress, height: 6)
          .padding(.horizontal, 16)
          .padding(.bottom, 14)
      }
    }
  }

  @ViewBuilder
  private func statusBadge(now: Int) -> some View {
    if resumeFraction != nil {
      Tag(text: "RESUME", solid: true)
    } else if let schedule {
      if schedule.isAiring(at: now) {
        LiveBadge(compact: true)
      } else if schedule.isUpcoming(at: now) {
        Tag(text: schedule.startDate.shortTime)
      } else if channel.isWithinCatchUpWindow(schedule, nowMs: now) {
        Tag(text: "CATCH UP")
      }
    }
  }

  @ViewBuilder
  private func caption(now: Int) -> some View {
    if let schedule {
      if showsChannelName {
        Text(channel.name.uppercased())
          .font(.cardKicker)
          .kerning(1.2)
          .foregroundStyle(.white.opacity(0.55 * textOpacity))
          .lineLimit(1)
      }
      Text(schedule.title)
        .font(.cardTitle)
        .foregroundStyle(.white.opacity(textOpacity))
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
      Text(metaLine(for: schedule, now: now))
        .font(.cardMeta)
        .foregroundStyle(.white.opacity(0.7 * textOpacity))
        .lineLimit(1)
      if showsDescription, let description = schedule.descriptionText {
        Text(description)
          .font(.cardMeta)
          .foregroundStyle(.white.opacity(0.6 * textOpacity))
          .lineLimit(2)
          .padding(.top, 4)
      }
    } else {
      Text(channel.name)
        .font(.cardTitle)
        .foregroundStyle(.white)
        .lineLimit(1)
      SkeletonBlock(cornerRadius: 6)
        .frame(width: scaledWidth * 0.5, height: 18)
    }
  }

  /// The programme's time and where it stands: how long is left while it airs, how soon it
  /// starts when that is within the hour, otherwise its day and time.
  private func metaLine(for schedule: Schedule, now: Int) -> String {
    if schedule.isAiring(at: now) {
      return "\(schedule.timeRangeText) · \(schedule.remainingMinutes(at: now)) min left"
    }
    if schedule.isUpcoming(at: now) {
      let minutes = schedule.minutesUntilStart(at: now)
      return minutes < 60 ? "\(schedule.timeRangeText) · Starts in \(minutes) min" : schedule.dayAndTimeRangeText
    }
    return schedule.dayAndTimeRangeText
  }
}

/// Compact channel tile in the same shape as the programme card: the logo on its near-black
/// aurora plate with the channel number and favourite mark, and the channel's name and what's
/// airing beneath it on the canvas.
struct ChannelTile: View {
  let channel: Channel
  let number: Int
  let schedule: Schedule?
  var isFavorite = false
  var width: CGFloat = Theme.channelTileWidth

  @Environment(LiveClock.self) private var clock
  @Environment(\.isFocused) private var isFocused
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .caption) private var textScale: CGFloat = 1

  private var scaledWidth: CGFloat { width * min(textScale, Theme.maxArtworkScale) }
  private var height: CGFloat { scaledWidth * 9 / 16 }

  var body: some View {
    let now = clock.nowMs
    VStack(alignment: .leading, spacing: 12) {
      ZStack {
        Rectangle()
          .fill(AuroraGeometry.palette(seed: channel.id).tileTint)
        ChannelLogo(channel: channel, height: scaledWidth * 0.24, platter: false)
          .padding(.horizontal, 28)
        VStack {
          HStack {
            Text(String(number))
              .font(.channelNumber)
              .foregroundStyle(Theme.textTertiary)
            Spacer()
            if isFavorite {
              Image(systemName: "heart.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            }
          }
          Spacer()
          if let schedule, schedule.isAiring(at: now) {
            ProgressBar(progress: schedule.progress(at: now), track: .white.opacity(0.12), height: 5)
          }
        }
        .padding(14)
      }
      .frame(width: scaledWidth, height: height)
      .cardChrome(isFocused: isFocused)

      CardCaption {
        Text(channel.name)
          .font(.cardTitle)
          .foregroundStyle(.white)
          .lineLimit(1)
        if let schedule {
          Text(schedule.title)
            .font(.cardMeta)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        } else {
          SkeletonBlock(cornerRadius: 5).frame(width: scaledWidth * 0.5, height: 16)
        }
      }
      .offset(y: isFocused ? 8 : 0)
    }
    .frame(width: scaledWidth)
    .animation(Theme.focusAnimation, value: isFocused)
  }
}

/// The words beneath a card, flush with the artwork's edge on the canvas. On focus they settle
/// onto a glass panel that reaches a little beyond the card, as the TV app's episode captions
/// do; at rest there is nothing behind them.
struct CardCaption<Content: View>: View {
  @ViewBuilder let content: () -> Content
  @Environment(\.isFocused) private var isFocused

  private static var inset: CGFloat { 14 }
  private static var verticalInset: CGFloat { 10 }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Self.inset)
    .padding(.vertical, Self.verticalInset)
    .background {
      if isFocused {
        Color.clear
          .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
          .transition(.opacity)
      }
    }
    // The panel overhangs the card; the words stay on the artwork's own edge.
    .padding(.horizontal, -Self.inset)
    .padding(.vertical, -Self.verticalInset)
  }
}

extension View {
  /// The chrome shared by the cards: the rounded clip, a hairline that brightens into a thin
  /// rim on focus, and the lift with the shadow and teal halo behind it.
  func cardChrome(isFocused: Bool, cornerRadius: CGFloat = Theme.cardRadius, scale: CGFloat = 1.08) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return self
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(Color.white.opacity(isFocused ? 0.75 : 0.1), lineWidth: isFocused ? 2 : 1)
      }
      .background {
        if isFocused {
          FocusHalo(cornerRadius: cornerRadius, scale: scale)
            .transition(.opacity)
        }
      }
      .scaleEffect(isFocused ? scale : 1)
      .zIndex(isFocused ? 1 : 0)
  }
}

/// The shadow and teal halo behind a focused card. It exists only while the card has focus, so
/// the many cards at rest on a screen never pay for the blur.
struct FocusHalo: View {
  let cornerRadius: CGFloat
  var scale: CGFloat = 1.08

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    ZStack {
      shape
        .fill(.black)
        .shadow(color: .black.opacity(0.6), radius: 34, y: 22)
      shape
        .fill(Theme.glow.opacity(0.3))
        .scaleEffect(scale)
        .blur(radius: 40)
    }
  }
}

/// Horizontal shelf of cards. Each shelf is its own focus section so vertical moves land on
/// the nearest card in the next shelf, and horizontal moves never jump rows. A shelf can open
/// scrolled to a particular item (e.g. the programme a details screen is about).
///
/// A shelf compares equal when its title and items are unchanged, and the screens that own
/// shelves apply `.equatable()` so a hero or header changing above the shelves never rebuilds
/// the cards below them. Anything the cards read from the stores still refreshes them, since
/// those reads are observed from inside the shelf's own body.
struct Shelf<Item: Identifiable & Equatable, Content: View>: View, Equatable {
  let title: String
  var subtitle: String? = nil
  let items: [Item]
  var initialItemID: Item.ID? = nil
  @ViewBuilder let content: (Item) -> Content

  static func == (lhs: Shelf, rhs: Shelf) -> Bool {
    lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
      && lhs.initialItemID == rhs.initialItemID && lhs.items == rhs.items
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(title: title, subtitle: subtitle)
        .padding(.horizontal, Theme.screenMargin)
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: Theme.cardSpacing) {
            ForEach(items) { item in
              content(item)
                .id(item.id)
            }
          }
          .padding(.top, 24)
          .padding(.bottom, 34)
        }
        .contentMargins(.horizontal, Theme.screenMargin, for: .scrollContent)
        .scrollClipDisabled()
        .onAppear {
          if let initialItemID { proxy.scrollTo(initialItemID, anchor: .leading) }
        }
      }
    }
    .focusSection()
  }
}

/// Long-press menu shared by programme cards everywhere.
struct ProgramContextMenu: View {
  let item: ContentStore.ProgramItem
  let lineup: [Channel]

  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock
  @Environment(FavoritesStore.self) private var favorites
  @Environment(PlaybackCoordinator.self) private var coordinator

  var body: some View {
    let now = clock.nowMs
    let channel = item.channel
    let schedule = item.schedule

    Button { coordinator.playLive(channel, lineup: lineup) } label: {
      Label("Watch \(channel.name) Live", systemImage: "play.fill")
    }
    if schedule.isAiring(at: now), channel.canStartOver {
      Button { coordinator.startOver(schedule, on: channel, lineup: lineup) } label: {
        Label("Start Over", systemImage: "backward.end.fill")
      }
    }
    if schedule.hasEnded(at: now), channel.isWithinCatchUpWindow(schedule, nowMs: now) {
      Button { coordinator.catchUp(schedule, on: channel, lineup: lineup) } label: {
        Label("Play from Start", systemImage: "gobackward")
      }
    }
    Button { coordinator.showDetails(item) } label: {
      Label("Details", systemImage: "info.circle")
    }
    Button { coordinator.openGuide(for: channel) } label: {
      Label("Open in Guide", systemImage: "list.bullet.rectangle")
    }
    Button { favorites.toggle(channel) } label: {
      Label(
        favorites.contains(channel.id) ? "Remove from Favorites" : "Add to Favorites",
        systemImage: favorites.contains(channel.id) ? "heart.slash" : "heart"
      )
    }
  }
}
