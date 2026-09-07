import Foundation

public struct EpgService {
  private let client: NetworkClient
  
  private let apiPrefix = "api-\(Constants.platform == "android" ? "android-tv" : "web")"
  
  private let baseURL: String
  
  init(client: NetworkClient, baseURL: String) {
    self.client = client
    self.baseURL = baseURL
  }
  
  public func getEpg(forChannel channel: Channel, startTime: Int?, endTime: Int?) async throws -> [Schedule] {
    let startOfToday = Date().startOfTheDay
    let endOfToday = Date().endOfTheDay
    
    let start = startTime ?? startOfToday.timestampSince1970
    let end = endTime ?? endOfToday.timestampSince1970
    
    let urlString = "https://\(apiPrefix).\(baseURL)/v1/events/epg?cid=\(channel.id)&fromTime=\(start)000&toTime=\(end)000"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url, headers: [
      "x-ucp-time-format": "timestamp"
    ])
    
    do {
      let response = try JSONDecoder().decode(Epg.self, from: data)
      
      return response.schedule.map { program in
        var clone = program
        clone.baseURL = baseURL
        return clone
      }
    } catch {
      throw NetworkError.decodingError
    }
  }
  
  public func getEpg(forChannels channels: [Channel], startTime: Int?, endTime: Int?) async throws -> [Int:[Schedule]] {
    let startOfToday = Date().startOfTheDay
    let endOfToday = Date().endOfTheDay
    
    let start = startTime ?? startOfToday.timestampSince1970
    let end = endTime ?? endOfToday.timestampSince1970
    
    var params = "";
    for channel in channels {
      params += "cid=\(channel.id)&"
    }
    
    let urlString = "https://\(apiPrefix).\(baseURL)/v1/events/epg?\(params)fromTime=\(start)000&toTime=\(end)000"
    guard let url = URL(string: urlString) else {
      throw NetworkError.invalidURL
    }
    
    let (data, _) = try await client.get(url, headers: [
      "x-ucp-time-format": "timestamp"
    ])
    
    do {
      let response = try JSONDecoder().decode([String: [Schedule]].self, from: data)
      var result: [Int: [Schedule]] = [:]
      for (key, channels) in response {
        result[Int(key)!] = channels.map { program in
          var clone = program
          clone.baseURL = baseURL
          return clone
        }
      }
      
      return result
    } catch {
      throw NetworkError.decodingError
    }
  }
}
