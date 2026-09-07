import Foundation

public struct Household: Identifiable, Codable {
  public let id: Int
  public let contractNumber: String
  public let buyerId: String
  public let packageName: String
}
