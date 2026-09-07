import SwiftUI

/// Home: a hero that follows the focused card, then shelves derived from the live guide.
/// Everything here is keyed by stable channel/programme ids so clock ticks and guide loads
/// update cards in place without disturbing focus or scroll.
struct HomeView: View {
  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock
  @Environment(FavoritesStore.self) private var favorites
  @Environment(WatchHistory.self) private var history
  @Environment(PlaybackCoordinator.self) private var coordinator

  @State private var featured: Featured?
  @State private var didClaimInitialFocus = false
  @FocusState private var focus: Focus?

  enum Focus: Hashable {
    case hero(HeroAction)
    case card(shelf: String, id: Int)
  }

  enum HeroAction: Hashable {
    case primary, secondary, guide
  }

  /// What the hero presents. A `nil` schedule means "whatever the channel is airing now".
  struct Featured: Equatable {
    var channel: Channel
    var schedule: Schedule?
    var resumeMs: Int?
  }

  var body: some View {
    ZStack {
      AmbientBackdrop(url: heroArtworkURL)

      switch (store.channelsState, store.hasChannels) {
      case (.failed(let message), false):
        StatusView(
          symbol: "antenna.radiowaves.left.and.right.slash",
          title: "Couldn't load your channels",
          message: message,
          actionTitle: "Try Again",
          action: { Task { await store.loadInitial() } }
        )
      case (_, false):
        HomeSkeleton()
      default:
        content
      }
    }
    .onAppear(perform: seedFeatured)
    .onChange(of: store.channels) { _, _ in seedFeatured() }
    .onChange(of: focus) { _, newValue in updateFeatured(for: newValue) }
    .onChange(of: clock.nowMs) { _, _ in store.recomputeShelves() }
  }

  // MARK: Content

  private var content: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: Theme.shelfSpacing) {
        if let featured {
          HeroView(
            featured: featured,
            focus: $focus,
            onPrimary: { heroPrimary(featured) },
            onSecondary: { heroSecondary(featured) },
            onGuide: { coordinator.openGuide(for: featured.channel) }
          )
          .padding(.top, Theme.contentTop)

          SpectrumLine()
            .padding(.horizontal, Theme.screenMargin)
            .padding(.top, -8)
        }

        let resumes = resumeItems
        if !resumes.isEmpty {
          Shelf(title: "Continue Watching", items: resumes) { entry in
            resumeCard(entry)
          }
        }

        let recents = recentChannels
        if !recents.isEmpty {
          Shelf(title: "Recently Watched", items: recents) { channel in
            channelCard(channel, shelf: "recent")
          }
        }

        Shelf(title: "On Now", subtitle: onNowSubtitle, items: store.shelves.onNow) { item in
          channelCard(item.channel, shelf: "onNow")
        }

        let favs = favorites.channels(in: store)
        if !favs.isEmpty {
          Shelf(title: "Favorites", items: favs) { channel in
            channelCard(channel, shelf: "favorites")
          }
        }

        if !store.shelves.upNext.isEmpty {
          Shelf(title: "Up Next", subtitle: "Starting soon", items: store.shelves.upNext) { item in
            programCard(item, shelf: "upNext")
          }
        }

        if !store.shelves.catchUp.isEmpty {
          Shelf(title: "Just Finished", subtitle: "Watch from the start", items: store.shelves.catchUp) { item in
            programCard(item, shelf: "catchUp")
          }
        }

        ForEach(store.browsableCategories) { category in
          Shelf(title: category.name, items: category.channels) { channel in
            channelCard(channel, shelf: "category-\(category.id)")
          }
        }
      }
      .padding(.bottom, 90)
    }
    .scrollClipDisabled()
    .defaultFocus($focus, .hero(.primary))
    .onAppear(perform: claimInitialFocus)
  }

  /// Content can appear after the skeleton, by which time the tab bar already took focus;
  /// the first time real content shows, land the viewer on the hero's primary action.
  private func claimInitialFocus() {
    guard !didClaimInitialFocus else { return }
    didClaimInitialFocus = true
    Task {
      try? await Task.sleep(for: .milliseconds(60))
      if focus == nil { focus = .hero(.primary) }
    }
  }

  private var onNowSubtitle: String? {
    store.todayLoadedFraction < 1 ? "Loading guide…" : nil
  }

  // MARK: Cards

  private func channelCard(_ channel: Channel, shelf: String) -> some View {
    let schedule = store.nowPlaying(channel)
    return Button {
      coordinator.playLive(channel, lineup: store.channels)
    } label: {
      ProgramCard(channel: channel, schedule: schedule)
    }
    .buttonStyle(.bare)
    .focused($focus, equals: .card(shelf: shelf, id: channel.id))
    .onPlayPauseCommand { coordinator.playLive(channel, lineup: store.channels) }
    .contextMenu {
      if let schedule {
        ProgramContextMenu(item: .init(channel: channel, schedule: schedule), lineup: store.channels)
      } else {
        Button { coordinator.playLive(channel, lineup: store.channels) } label: {
          Label("Watch Live", systemImage: "play.fill")
        }
        Button { favorites.toggle(channel) } label: {
          Label(favorites.contains(channel.id) ? "Remove from Favorites" : "Add to Favorites", systemImage: "heart")
        }
      }
    }
  }

  private func programCard(_ item: ContentStore.ProgramItem, shelf: String) -> some View {
    Button {
      coordinator.open(item, nowMs: clock.nowMs, lineup: store.channels)
    } label: {
      ProgramCard(channel: item.channel, schedule: item.schedule)
    }
    .buttonStyle(.bare)
    .focused($focus, equals: .card(shelf: shelf, id: item.schedule.id))
    .onPlayPauseCommand { coordinator.open(item, nowMs: clock.nowMs, lineup: store.channels) }
    .contextMenu { ProgramContextMenu(item: item, lineup: store.channels) }
  }

  private func resumeCard(_ entry: ResumeItem) -> some View {
    Button {
      coordinator.catchUp(entry.schedule, on: entry.channel, offsetMs: entry.positionMs, lineup: store.channels)
    } label: {
      ProgramCard(channel: entry.channel, schedule: entry.schedule, resumeFraction: entry.fraction)
    }
    .buttonStyle(.bare)
    .focused($focus, equals: .card(shelf: "resume", id: entry.schedule.id))
    .onPlayPauseCommand {
      coordinator.catchUp(entry.schedule, on: entry.channel, offsetMs: entry.positionMs, lineup: store.channels)
    }
    .contextMenu {
      Button { coordinator.catchUp(entry.schedule, on: entry.channel, lineup: store.channels) } label: {
        Label("Play from Start", systemImage: "gobackward")
      }
      Button(role: .destructive) { history.removeResume(entry.schedule.id) } label: {
        Label("Remove from Continue Watching", systemImage: "trash")
      }
    }
  }

  // MARK: Derived items

  struct ResumeItem: Identifiable {
    let channel: Channel
    let schedule: Schedule
    let positionMs: Int
    let fraction: Double
    var id: Int { schedule.id }
  }

  private var resumeItems: [ResumeItem] {
    let now = clock.nowMs
    return history.resumes.compactMap { entry in
      guard let channel = store.channel(entry.channelID), channel.canCatchUp else { return nil }
      let schedule = store.schedule(withID: entry.scheduleID, channelID: entry.channelID)
        ?? Schedule(
          id: entry.scheduleID, title: entry.title, originalTitle: nil, shortDescription: nil,
          channelId: entry.channelID, startTime: entry.startTime, endTime: entry.endTime,
          seasonNumber: nil, episodeNumber: nil, live: false,
          images: entry.posterPath.map { [ChannelImage(path: $0, width: 480, height: 270, size: "XL", type: "EVENT_16_9")] } ?? [],
          baseURL: channel.baseURL
        )
      guard channel.isWithinCatchUpWindow(schedule, nowMs: now) else { return nil }
      return ResumeItem(channel: channel, schedule: schedule, positionMs: entry.positionMs, fraction: entry.fraction)
    }
  }

  private var recentChannels: [Channel] {
    history.recentChannelIDs.compactMap { store.channel($0) }
  }

  // MARK: Hero

  private var heroArtworkURL: URL? {
    guard let featured else { return nil }
    let schedule = featured.schedule ?? store.nowPlaying(featured.channel)
    return schedule?.posterURL ?? featured.channel.logoURL
  }

  private func seedFeatured() {
    guard featured == nil, let first = store.channels.first else { return }
    let channel = history.lastChannelID.flatMap { store.channel($0) } ?? first
    featured = Featured(channel: channel, schedule: nil, resumeMs: nil)
  }

  private func updateFeatured(for focus: Focus?) {
    guard case .card(let shelf, let id) = focus else { return }
    switch shelf {
    case "upNext":
      if let item = store.shelves.upNext.first(where: { $0.id == id }) {
        featured = Featured(channel: item.channel, schedule: item.schedule, resumeMs: nil)
      }
    case "catchUp":
      if let item = store.shelves.catchUp.first(where: { $0.id == id }) {
        featured = Featured(channel: item.channel, schedule: item.schedule, resumeMs: nil)
      }
    case "resume":
      if let item = resumeItems.first(where: { $0.id == id }) {
        featured = Featured(channel: item.channel, schedule: item.schedule, resumeMs: item.positionMs)
      }
    default:
      if let channel = store.channel(id) {
        featured = Featured(channel: channel, schedule: nil, resumeMs: nil)
      }
    }
  }

  private func heroPrimary(_ featured: Featured) {
    let now = clock.nowMs
    let channel = featured.channel
    guard let schedule = featured.schedule ?? store.nowPlaying(channel) else {
      coordinator.playLive(channel, lineup: store.channels)
      return
    }
    coordinator.open(.init(channel: channel, schedule: schedule), nowMs: now, lineup: store.channels, resumeMs: featured.resumeMs)
  }

  private func heroSecondary(_ featured: Featured) {
    let now = clock.nowMs
    let channel = featured.channel
    let schedule = featured.schedule ?? store.nowPlaying(channel)
    if let schedule, schedule.isAiring(at: now), channel.canStartOver {
      coordinator.startOver(schedule, on: channel, lineup: store.channels)
    } else {
      coordinator.playLive(channel, lineup: store.channels)
    }
  }
}

// MARK: - Hero

struct HeroView: View {
  let featured: HomeView.Featured
  var focus: FocusState<HomeView.Focus?>.Binding
  let onPrimary: () -> Void
  let onSecondary: () -> Void
  let onGuide: () -> Void

  @Environment(ContentStore.self) private var store
  @Environment(LiveClock.self) private var clock

  private var schedule: Schedule? { featured.schedule ?? store.nowPlaying(featured.channel) }

  var body: some View {
    let now = clock.nowMs
    let channel = featured.channel
    let schedule = schedule

    HStack(alignment: .center, spacing: 60) {
      VStack(alignment: .leading, spacing: 22) {
        HStack(spacing: 16) {
          ChannelLogo(channel: channel, height: 44, platter: false)
          Text(channel.name)
            .font(.heroMeta)
            .foregroundStyle(Theme.textSecondary)
          Text("·")
            .foregroundStyle(Theme.textTertiary)
          Text("Channel \(store.channelNumber(channel))")
            .font(.heroMeta)
            .foregroundStyle(Theme.textTertiary)
        }

        Text(schedule?.title ?? channel.name)
          .font(.heroTitle)
          .foregroundStyle(Theme.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(0.7)
          .id(schedule?.id ?? channel.id)
          .transition(.opacity)

        if let schedule {
          HStack(spacing: 16) {
            if schedule.isAiring(at: now) {
              LiveBadge()
            } else if schedule.isUpcoming(at: now) {
              Tag(text: schedule.startDate.relativeDayLabel().uppercased())
            } else if channel.isWithinCatchUpWindow(schedule, nowMs: now) {
              Tag(text: "CATCH UP")
            }
            Text(schedule.timeRangeText)
              .font(.heroMeta)
              .foregroundStyle(Theme.textSecondary)
            if let subtitle = schedule.subtitleText {
              Text(subtitle)
                .font(.heroMeta)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
            if schedule.isAiring(at: now) {
              Text("\(schedule.remainingMinutes(at: now)) min left")
                .font(.heroMeta)
                .foregroundStyle(Theme.textTertiary)
            }
          }

          if schedule.isAiring(at: now) {
            ProgressBar(progress: schedule.progress(at: now), height: 6)
              .frame(width: 560)
          } else if let resume = featured.resumeMs {
            ProgressBar(progress: Double(resume) / Double(max(1, schedule.durationMs)), height: 6)
              .frame(width: 560)
          }

          if let description = schedule.descriptionText {
            Text(description)
              .font(.heroBody)
              .foregroundStyle(Theme.textSecondary)
              .lineLimit(3)
              .frame(maxWidth: 900, alignment: .leading)
          }
        } else {
          SkeletonBlock(cornerRadius: 8).frame(width: 420, height: 28)
          SkeletonBlock(cornerRadius: 8).frame(width: 760, height: 24)
        }

        HStack(spacing: 20) {
          Button(action: onPrimary) {
            Label(primaryTitle(schedule: schedule, now: now), systemImage: primarySymbol(schedule: schedule, now: now))
          }
          .buttonStyle(.prominentPill)
          .focused(focus, equals: .hero(.primary))

          if let secondary = secondaryTitle(schedule: schedule, now: now) {
            Button(action: onSecondary) {
              Label(secondary.0, systemImage: secondary.1)
            }
            .buttonStyle(.pill)
            .focused(focus, equals: .hero(.secondary))
          }

          Button(action: onGuide) {
            Label("Guide", systemImage: "list.bullet.rectangle")
          }
          .buttonStyle(.pill)
          .focused(focus, equals: .hero(.guide))
        }
        .padding(.top, 6)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      artwork
    }
    .padding(.horizontal, Theme.screenMargin)
    .frame(height: 470)
    .focusSection()
    .animation(Theme.crossfade, value: schedule?.id)
  }

  private var artwork: some View {
    let url = schedule?.posterURL
    return ZStack {
      RemoteImage(url: url) {
        ZStack {
          ArtworkPlaceholder(seed: featured.channel.id)
          ChannelLogo(channel: featured.channel, height: 110, platter: false)
        }
      }
      .id(url)
      .transition(.opacity)
    }
    .frame(width: 640, height: 360)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.55), radius: 40, y: 24)
    .shadow(color: Theme.glow.opacity(0.18), radius: 70)
    .animation(Theme.crossfade, value: url)
  }

  private func primaryTitle(schedule: Schedule?, now: Int) -> String {
    guard let schedule else { return "Watch Live" }
    if schedule.isAiring(at: now) { return "Watch Live" }
    if schedule.hasEnded(at: now) {
      if featured.channel.isWithinCatchUpWindow(schedule, nowMs: now) {
        return featured.resumeMs != nil ? "Resume" : "Play from Start"
      }
      return "Watch Live"
    }
    return "Details"
  }

  private func primarySymbol(schedule: Schedule?, now: Int) -> String {
    guard let schedule else { return "play.fill" }
    if schedule.isUpcoming(at: now) { return "info.circle" }
    if schedule.hasEnded(at: now), featured.channel.isWithinCatchUpWindow(schedule, nowMs: now) { return "gobackward" }
    return "play.fill"
  }

  private func secondaryTitle(schedule: Schedule?, now: Int) -> (String, String)? {
    guard let schedule else { return nil }
    if schedule.isAiring(at: now) {
      return featured.channel.canStartOver ? ("Start Over", "backward.end.fill") : nil
    }
    return ("Watch Live", "play.fill")
  }
}

// MARK: - Skeleton

struct HomeSkeleton: View {
  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: Theme.shelfSpacing) {
        HStack(alignment: .center, spacing: 60) {
          VStack(alignment: .leading, spacing: 22) {
            SkeletonBlock(cornerRadius: 8).frame(width: 260, height: 30)
            SkeletonBlock(cornerRadius: 12).frame(width: 760, height: 70)
            SkeletonBlock(cornerRadius: 8).frame(width: 520, height: 28)
            SkeletonBlock(cornerRadius: 8).frame(width: 860, height: 26)
            HStack(spacing: 20) {
              SkeletonBlock(cornerRadius: 30).frame(width: 220, height: 62)
              SkeletonBlock(cornerRadius: 30).frame(width: 180, height: 62)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          SkeletonBlock(cornerRadius: 18).frame(width: 640, height: 360)
        }
        .padding(.horizontal, Theme.screenMargin)
        .frame(height: 470)
        .padding(.top, Theme.contentTop)

        ForEach(0..<2, id: \.self) { _ in
          VStack(alignment: .leading, spacing: 18) {
            SkeletonBlock(cornerRadius: 8)
              .frame(width: 240, height: 34)
              .padding(.horizontal, Theme.screenMargin)
            HStack(spacing: Theme.cardSpacing) {
              ForEach(0..<5, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 14) {
                  SkeletonBlock(cornerRadius: Theme.cardRadius)
                    .frame(width: Theme.programCardWidth, height: Theme.programCardWidth * 9 / 16)
                  SkeletonBlock(cornerRadius: 6).frame(width: 260, height: 24)
                  SkeletonBlock(cornerRadius: 6).frame(width: 180, height: 20)
                }
              }
            }
            .padding(.horizontal, Theme.screenMargin)
          }
        }
      }
    }
    .allowsHitTesting(false)
  }
}
