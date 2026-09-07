import Foundation

public enum NetworkError: Error {
  case invalidURL
  case noData
  case decodingError
  case unknown
  case missingParams
  case notConfigured
}
