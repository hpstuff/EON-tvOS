import Foundation
import EONKit
import Observation

/// The active profile's favourite channels, kept by the platform so they match the web app
/// and other devices. Toggles apply at once and are rolled back if the platform refuses them.
@Observable
final class FavoritesStore {
  /// Favourites used to live only on the device; the platform's list now wins.
  private static let legacyKey = "eon.favorites.channelIDs"

  private(set) var ids: [Int] = []
  /// Set when a change couldn't be saved; the UI shows it once and clears it.
  var lastError: String?

  private var repository: FavoritesRepository?
  private var listID: FavoriteList.ID?

  init() {
    UserDefaults.standard.removeObject(forKey: Self.legacyKey)
  }

  var isEmpty: Bool { ids.isEmpty }

  func contains(_ channelID: Int) -> Bool { ids.contains(channelID) }

  /// Starts following the signed-in profile's list.
  func attach(_ repository: FavoritesRepository) async {
    self.repository = repository
    await reload()
  }

  /// Forgets the list, on sign-out or before switching profile.
  func detach() {
    repository = nil
    listID = nil
    ids = []
    lastError = nil
  }

  func reload() async {
    guard let repository else { return }
    do {
      let list = try await repository.getFavorites()
      listID = list.id
      ids = list.channelIDs
    } catch {
      // Keep what is shown; the next toggle or refresh tries again.
    }
  }

  func toggle(_ channel: Channel) {
    let wasFavorite = contains(channel.id)
    apply(channel.id, favorite: !wasFavorite)
    Task {
      do {
        try await save(channel.id, favorite: !wasFavorite)
      } catch {
        apply(channel.id, favorite: wasFavorite)
        lastError = wasFavorite
          ? "Couldn't remove \(channel.name) from Favorites."
          : "Couldn't add \(channel.name) to Favorites."
      }
    }
  }

  /// Removes every favourite in one call.
  func removeAll() {
    let previous = ids
    guard !previous.isEmpty else { return }
    ids = []
    Task {
      do {
        let list = try await currentListID()
        try await repository?.update(list: list, adding: [], removing: previous)
      } catch {
        ids = previous
        lastError = "Couldn't clear Favorites."
      }
    }
  }

  /// Favourite channels in the platform's order, resolved against the current line-up.
  func channels(in store: ContentStore) -> [Channel] {
    ids.compactMap { store.channelsByID[$0] }
  }

  private func apply(_ channelID: Int, favorite: Bool) {
    if favorite {
      if !ids.contains(channelID) { ids.append(channelID) }
    } else {
      ids.removeAll { $0 == channelID }
    }
  }

  private func save(_ channelID: Int, favorite: Bool) async throws {
    guard let repository else { throw NetworkError.notConfigured }
    let list = try await currentListID()
    try await repository.update(
      list: list,
      adding: favorite ? [channelID] : [],
      removing: favorite ? [] : [channelID]
    )
  }

  private func currentListID() async throws -> FavoriteList.ID {
    if let listID { return listID }
    guard let repository else { throw NetworkError.notConfigured }
    let list = try await repository.getFavorites()
    listID = list.id
    return list.id
  }
}
