import Foundation

struct Epg: Codable {
  let schedule: [Schedule]

  struct Epg: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int?
    init?(intValue: Int) {
      self.intValue = intValue
      self.stringValue = String(intValue)
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Epg.self)
    // just take the first (and presumably only) key
    guard let firstKey = container.allKeys.first else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "No keys found")
      )
    }
    schedule = try container.decode([Schedule].self, forKey: firstKey)
  }
}
