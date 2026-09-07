import Foundation

struct LoggingInterceptor: Interceptor {
  func interceptRequest(_ request: URLRequest) async throws -> URLRequest {
    print("➡️ Request: \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
    if request.allHTTPHeaderFields != nil {
      print("=== Headers =============")
      for (key,value) in request.allHTTPHeaderFields! {
        print("\(key): \(value)")
      }
      print("======================")
    }
    if request.httpBody != nil {
      print("=== BODY =============")
      if let returnData = String(data: request.httpBody!, encoding: .utf8) {
        print("\(returnData)")
      }else {
        print("")
      }
      print("======================")
    }
    return request
  }
  
  func interceptResponse(_ data: Data, _ response: URLResponse, for request: URLRequest) async throws -> (Data, URLResponse) {
    if let http = response as? HTTPURLResponse {
      print("⬅️ Response: \(http.statusCode) from \(http.url?.absoluteString ?? "")")
//      print("=== Result =============")
//      print("\(String(data: data, encoding: .utf8)!)")
//      print("========================")
    }
    return (data, response)
  }
}
