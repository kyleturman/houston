import Foundation

/// Comprehensive error classification for network operations
/// Enables user-friendly error messages and appropriate retry strategies
///
/// **Error Categories:**
/// - **Network Errors**: Connection issues, timeouts
/// - **Server Errors**: HTTP 5xx errors
/// - **Client Errors**: HTTP 4xx errors (auth, validation)
/// - **Data Errors**: Decoding failures
///
/// Usage:
/// ```swift
/// do {
///     let data = try await apiClient.fetchData()
/// } catch let error as NetworkError {
///     switch error {
///     case .noConnection:
///         showToast("No internet connection", type: .error)
///     case .timeout:
///         showToast("Request timed out", type: .warning)
///     case .serverError(let code, _):
///         showToast("Server error (\(code))", type: .error)
///     case .unauthorized:
///         // Token refresh or re-login
///     case .decodingFailed:
///         showToast("Invalid response from server", type: .error)
///     default:
///         showToast("Something went wrong", type: .error)
///     }
/// }
/// ```
enum NetworkError: Error, LocalizedError {
    /// No internet connection available
    case noConnection

    /// Request timed out waiting for response
    case timeout

    /// Server returned 5xx error
    case serverError(statusCode: Int, message: String?)

    /// Authentication failure (401/403)
    case unauthorized(message: String?)

    /// Resource not found (404)
    case notFound

    /// Client error (400, 422, etc.)
    case clientError(statusCode: Int, message: String?)

    /// Failed to decode response data
    case decodingFailed(underlyingError: Error?)

    /// Invalid URL or request configuration
    case invalidRequest(message: String)

    /// Unknown error
    case unknown(error: Error)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection. Please check your network settings."

        case .timeout:
            return "The request timed out. Please try again."

        case .serverError(let code, let message):
            if let message = message {
                return "Server error (\(code)): \(message)"
            }
            return "Server error (\(code)). Please try again later."

        case .unauthorized(let message):
            if let message = message {
                return "Authentication failed: \(message)"
            }
            return "Authentication failed. Please sign in again."

        case .notFound:
            return "The requested resource was not found."

        case .clientError(let code, let message):
            if let message = message {
                return "Request failed (\(code)): \(message)"
            }
            return "Request failed (\(code))."

        case .decodingFailed:
            return "Failed to process server response."

        case .invalidRequest(let message):
            return "Invalid request: \(message)"

        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    // MARK: - Retry Strategy

    /// Whether this error should trigger an automatic retry
    var shouldRetry: Bool {
        switch self {
        case .noConnection, .timeout, .serverError:
            return true
        case .unauthorized, .notFound, .clientError, .decodingFailed, .invalidRequest, .unknown:
            return false
        }
    }

    /// User-friendly message for UI display
    var userFriendlyMessage: String {
        switch self {
        case .noConnection:
            return "No internet connection"
        case .timeout:
            return "Connection timed out"
        case .serverError:
            return "Server error"
        case .unauthorized:
            return "Authentication error"
        case .notFound:
            return "Not found"
        case .clientError:
            return "Request failed"
        case .decodingFailed:
            return "Invalid response"
        case .invalidRequest:
            return "Invalid request"
        case .unknown:
            return "Something went wrong"
        }
    }

    // MARK: - Factory Methods

    /// Create NetworkError from URLError
    static func from(urlError: URLError) -> NetworkError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .noConnection

        case .timedOut:
            return .timeout

        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .noConnection

        case .userAuthenticationRequired:
            return .unauthorized(message: urlError.localizedDescription)

        default:
            return .unknown(error: urlError)
        }
    }

    /// Create NetworkError from HTTP response
    static func from(statusCode: Int, data: Data?) -> NetworkError {
        let message = data.flatMap { String(data: $0, encoding: .utf8) }

        switch statusCode {
        case 200..<300:
            // Success codes shouldn't create errors
            return .unknown(error: NSError(domain: "NetworkError", code: statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected success status in error handler"
            ]))

        case 401, 403:
            return .unauthorized(message: message)

        case 404:
            return .notFound

        case 400, 422:
            return .clientError(statusCode: statusCode, message: message)

        case 500..<600:
            return .serverError(statusCode: statusCode, message: message)

        default:
            return .unknown(error: NSError(domain: "HTTPError", code: statusCode, userInfo: [
                NSLocalizedDescriptionKey: message ?? "HTTP error \(statusCode)"
            ]))
        }
    }

    /// Create NetworkError from decoding error
    static func decodingError(_ error: Error) -> NetworkError {
        return .decodingFailed(underlyingError: error)
    }
}
