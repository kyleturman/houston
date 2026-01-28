import Foundation

// MARK: - API Response Models
// Import shared JSON:API wrappers (defined in Core/Models/API/)
// These models are shared across APIClient, IntentAPIClient, and extensions

/// Lightweight networking core shared between full APIClient and IntentAPIClient
/// Contains only the essential networking infrastructure without business logic
final class ExtensionAPIClient: @unchecked Sendable {
    let baseURL: URL
    private let deviceTokenProvider: (() -> String?)?
    private let userTokenProvider: (() -> String?)?

    init(
        baseURL: URL,
        deviceTokenProvider: (() -> String?)? = nil,
        userTokenProvider: (() -> String?)? = nil
    ) {
        self.baseURL = baseURL
        self.deviceTokenProvider = deviceTokenProvider
        self.userTokenProvider = userTokenProvider
    }

    // MARK: - Networking

    /// Auth mode for API requests
    enum Auth {
        case none
        case device
        case user
    }

    /// API errors
    enum APIError: Error, LocalizedError {
        case invalidURL
        case requestFailed(statusCode: Int?, message: String?)
        case decodingFailed
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .requestFailed(let statusCode, let message):
                return "Request failed (\(statusCode ?? 0)): \(message ?? "Unknown error")"
            case .decodingFailed:
                return "Failed to decode response"
            case .notAuthenticated:
                return "Not authenticated"
            }
        }
    }

    /// Make HTTP request with authentication
    func request(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        auth: Auth = .device
    ) async throws -> (Data, URLResponse) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Add authentication header
        switch auth {
        case .device:
            guard let token = deviceTokenProvider?() else {
                throw APIError.notAuthenticated
            }
            request.setValue("Device \(token)", forHTTPHeaderField: "Authorization")

        case .user:
            guard let token = userTokenProvider?() else {
                throw APIError.notAuthenticated
            }
            request.setValue("User \(token)", forHTTPHeaderField: "Authorization")

        case .none:
            break
        }

        return try await URLSession.shared.data(for: request)
    }
}

// MARK: - JSON:API Wrappers
// Defined in: Core/Models/API/JSONAPIWrappers.swift
// (JSONAPISingle, JSONAPIList are imported from shared models)
