import Foundation

struct HeadersInterceptor: Interceptor {
  func interceptRequest(_ request: URLRequest) async throws -> URLRequest {
    var modified = request
    
    if let _ = request.value(forHTTPHeaderField: "Content-Type") {} else {
      modified.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    
    return request
  }
}
