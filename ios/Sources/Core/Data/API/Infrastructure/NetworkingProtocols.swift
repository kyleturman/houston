import Foundation

// MARK: - URLSession Protocol for Testability
//
// This protocol allows dependency injection of URLSession for unit testing.
// Use MockURLSession conforming to this protocol to test API calls without network.

/// Protocol for URLSession to enable dependency injection and testability
protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Extension to make URLSession conform to URLSessionProtocol
extension URLSession: URLSessionProtocol {}
