//
//  CacheInterceptor.swift
//  EON TV
//
//  Created by Rumen Russanov on 4.11.25.
//


import Foundation

final class CacheInterceptor: Interceptor {
    private let cache: URLCache

    init(cache: URLCache = .shared) {
        self.cache = cache
    }

    // MARK: - Request

    func interceptRequest(_ request: URLRequest) async throws -> URLRequest {
        // Only cache GET requests
      guard request.httpMethod?.uppercased() == "GET", (request.url?.absoluteString.contains("epg") ?? false) else {
          return request
      }

      // Check cache for existing response
      if let cachedResponse = cache.cachedResponse(for: request) {
        // You can add custom logging or metrics here
        print("💾 [CacheInterceptor] Returning cached data for: \(request.url?.absoluteString ?? "")")

        // Short-circuit by throwing a "pseudo response" so upper layer can detect cache hit
        throw CachedResponseError.cachedResponse(cachedResponse)
      }

      return request
    }

    // MARK: - Response

    func interceptResponse(_ data: Data, _ response: URLResponse, for request: URLRequest) async throws -> (Data, URLResponse) {
        guard request.httpMethod?.uppercased() == "GET", (request.url?.absoluteString.contains("epg") ?? false) else {
            return (data, response)
        }

        // Only successful payloads are worth keeping; caching a 401 body would poison the day.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return (data, response)
        }

        // Store in cache
        let cached = CachedURLResponse(response: response, data: data)
        cache.storeCachedResponse(cached, for: request)

        print("🗂️ [CacheInterceptor] Cached response for: \(request.url?.absoluteString ?? "")")

        return (data, response)
    }

    // MARK: - Error

    func interceptError(_ error: Error, for request: URLRequest) async throws -> (Data, URLResponse) {
        guard request.httpMethod?.uppercased() == "GET" else {
            throw error
        }

        // If there's cached data, return it even when network fails
        if let cached = cache.cachedResponse(for: request) {
            print("⚠️ [CacheInterceptor] Network failed, returning cached data for: \(request.url?.absoluteString ?? "")")
            return (cached.data, cached.response)
        }

        throw error
    }
}

// MARK: - Helper

enum CachedResponseError: Error {
    case cachedResponse(CachedURLResponse)
}
