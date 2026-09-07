import Foundation

final class NetworkClient {
  private let session: URLSession
  private var interceptors: [Interceptor]

  init(session: URLSession = .shared, interceptors: [Interceptor]) {
    self.session = session
    self.interceptors = interceptors
  }
  
  func addInterceptor(interceptor: Interceptor) {
    self.interceptors.append(interceptor)
  }

  func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
    let adapted = try await interceptors.asyncReduce(request) { req, interceptor in
      do {
        return try await interceptor.interceptRequest(req)
      } catch {
        throw error
      }
    }

    do {
      let (data, response) = try await session.data(for: adapted)
      
      return try await interceptors.asyncReduce((data, response)) { result, interceptor in
        try await interceptor.interceptResponse(result.0, result.1, for: adapted)
      }
    } catch {
      for interceptor in interceptors {
        do {
          return try await interceptor.interceptError(error, for: adapted)
        } catch {
          continue
        }
      }
      throw error
    }
  }
  
  func get(_ url: URL, headers: [String:String]? = nil) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    
    if let headers = headers {
      for (key, value) in headers {
        request.addValue(value, forHTTPHeaderField: key)
      }
    }
    do {
      return try await send(request)
    } catch let CachedResponseError.cachedResponse(cached) {
      return (cached.data, cached.response)
    }
  }
  
  func post(_ url: URL, data: Data? = nil, headers: [String:String]? = nil) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: url)
    
    request.httpMethod = "POST"
    request.httpBody = data
    
    if let headers = headers {
      for (key, value) in headers {
        request.addValue(value, forHTTPHeaderField: key)
      }
    }
    
    return try await send(request)
  }
}

extension Sequence {
  func asyncReduce<Result>(
    _ initialResult: Result,
    _ nextPartialResult: (Result, Element) async throws -> Result
  ) async rethrows -> Result {
    var result = initialResult
    for element in self {
      result = try await nextPartialResult(result, element)
    }
    return result
  }
}

protocol Interceptor {
  func interceptRequest(_ request: URLRequest) async throws -> URLRequest
  func interceptResponse(_ data: Data, _ response: URLResponse, for request: URLRequest) async throws -> (Data, URLResponse)
  func interceptError(_ error: Error, for request: URLRequest) async throws -> (Data, URLResponse)
}

extension Interceptor {
    func interceptRequest(_ request: URLRequest) async throws -> URLRequest { request }
    func interceptResponse(_ data: Data, _ response: URLResponse, for request: URLRequest) async throws -> (Data, URLResponse) { (data, response) }
    func interceptError(_ error: Error, for request: URLRequest) async throws -> (Data, URLResponse) { throw error }
}
