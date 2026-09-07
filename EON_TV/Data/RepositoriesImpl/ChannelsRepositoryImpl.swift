import Foundation

public class ChannelsRepositoryImpl: ChannelsRepository {
  private let channelsService: ChannelsService
  
  init(channelsService: ChannelsService) {
    self.channelsService = channelsService
  }
  
  public func getChannels() async throws -> [Channel] {
    let categories = try await channelsService.getCategries()
    let channels = try await channelsService.getChannels()
    
    if let defaultCategory = categories.first(where: { category in category.defaultList }) {
      return defaultCategory.channels.map { order in channels.first { channel in order.id == channel.id }! }.filter { channel in
        channel.subscribed
      }
    }

    return channels
  }

  public func getCategories() async throws -> [ChannelCategory] {
    let categories = try await channelsService.getCategries()
    let channels = try await channelsService.getChannels()

    let channelsByID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    return categories.compactMap { category in
      let resolvedChannels = category.channels
        .sorted { $0.position < $1.position }
        .compactMap { order in channelsByID[order.id] }
        .filter { channel in channel.subscribed }

      guard !resolvedChannels.isEmpty else { return nil }

      return ChannelCategory(
        id: category.id,
        name: category.name,
        defaultList: category.defaultList,
        channels: resolvedChannels
      )
    }
  }
}
