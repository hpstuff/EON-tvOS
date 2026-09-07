public protocol ChannelsRepository {
  func getChannels() async throws -> [Channel]
  func getCategories() async throws -> [ChannelCategory]
}
