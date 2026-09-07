import Foundation
import Observation

/// Locally kept favourite channels. The platform has no favourites API, so this lives on
/// the device and is honoured across Home, Channels, the Guide and the player.
@Observable
final class FavoritesStore {
  private static let key = "eon.favorites.channelIDs"

  private(set) var ids: [Int] {
    didSet { UserDefaults.standard.set(ids, forKey: Self.key) }
  }

  init() {
    ids = UserDefaults.standard.array(forKey: Self.key) as? [Int] ?? []
  }

  var isEmpty: Bool { ids.isEmpty }

  func contains(_ channelID: Int) -> Bool { ids.contains(channelID) }

  func toggle(_ channel: Channel) {
    if let index = ids.firstIndex(of: channel.id) {
      ids.remove(at: index)
    } else {
      ids.append(channel.id)
    }
  }

  /// Favourite channels in the order they were added, resolved against the current line-up.
  func channels(in store: ContentStore) -> [Channel] {
    ids.compactMap { store.channelsByID[$0] }
  }
}
