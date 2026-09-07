import Foundation

/// A channel category paired with its resolved, subscribed channels — ready for display.
///
/// Built in the data layer by matching a `Category`'s `ChannelOrder` entries against the
/// full channel list, ordering them by `position`, and keeping only subscribed channels.
public struct ChannelCategory: Identifiable {
  public let id: Int
  public let name: String
  public let defaultList: Bool
  public let channels: [Channel]

  public init(id: Int, name: String, defaultList: Bool, channels: [Channel]) {
    self.id = id
    self.name = name
    self.defaultList = defaultList
    self.channels = channels
  }
}
