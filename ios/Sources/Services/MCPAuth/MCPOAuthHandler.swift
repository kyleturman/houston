import Foundation
import SafariServices
import UIKit
import AuthenticationServices

// MARK: - OAuth Handler Protocol

/// Protocol for MCP OAuth handlers
/// Different providers can implement this to provide custom OAuth flows
@MainActor
protocol MCPOAuthHandlerProtocol {
    /// Present the OAuth flow to the user
    /// - Parameters:
    ///   - linkToken: The link token or auth token from the backend
    ///   - config: Provider-specific configuration from backend
    ///   - presentingViewController: The view controller to present from
    ///   - completion: Called with (publicToken, metadata) on success, or error on failure
    func present(
        linkToken: String,
        config: [String: Any]?,
        from presentingViewController: UIViewController,
        completion: @escaping (Result<(publicToken: String, metadata: [String: Any]), Error>) -> Void
    )
}

// MARK: - Handler Registry

/// Singleton registry for OAuth handlers
/// Maps handler type strings to handler implementations
@MainActor
class MCPOAuthHandlerRegistry {
    static let shared = MCPOAuthHandlerRegistry()

    private var handlers: [String: MCPOAuthHandlerProtocol] = [:]

    private init() {
        // Register default handlers
        registerHandler(WebAuthOAuthHandler(), for: "oauth2")
        registerHandler(PlaidLinkHandler.shared, for: "plaid_link")
    }

    /// Register a handler for a specific type
    func registerHandler(_ handler: MCPOAuthHandlerProtocol, for type: String) {
        handlers[type] = handler
    }

    /// Get a handler for a specific type
    func handler(for type: String) -> MCPOAuthHandlerProtocol? {
        return handlers[type]
    }
}

// MARK: - Web Authentication OAuth Handler

/// Handler for OAuth2 flows using ASWebAuthenticationSession
/// Provides a native, integrated OAuth experience with callback handling
@MainActor
class WebAuthOAuthHandler: NSObject, MCPOAuthHandlerProtocol, ASWebAuthenticationPresentationContextProviding {
    private var presentingViewController: UIViewController?
    private var authSession: ASWebAuthenticationSession?

    func present(
        linkToken: String,
        config: [String: Any]?,
        from presentingViewController: UIViewController,
        completion: @escaping (Result<(publicToken: String, metadata: [String: Any]), Error>) -> Void
    ) {
        self.presentingViewController = presentingViewController

        // For OAuth2, linkToken is the authorization URL
        guard let authorizeURL = URL(string: linkToken) else {
            completion(.failure(MCPOAuthError.invalidURL))
            return
        }

        // Extract callback scheme from config or use default
        let callbackScheme = (config?["callback_scheme"] as? String) ?? "life-assistant"

        // Create web authentication session
        let session = ASWebAuthenticationSession(
            url: authorizeURL,
            callbackURLScheme: callbackScheme
        ) { callbackURL, error in
            if let error = error {
                if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    completion(.failure(MCPOAuthError.userCancelled))
                } else {
                    completion(.failure(error))
                }
                return
            }

            guard let callbackURL = callbackURL else {
                completion(.failure(MCPOAuthError.invalidResponse))
                return
            }

            // Parse the callback URL for status
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []

            // Check for error in callback
            if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
                let errorDescription = queryItems.first(where: { $0.name == "error_description" })?.value ?? errorParam
                completion(.failure(MCPOAuthError.providerError(errorDescription)))
                return
            }

            // Check for success - server already exchanged the code for tokens
            if queryItems.first(where: { $0.name == "status" })?.value == "success" {
                let serverId = queryItems.first(where: { $0.name == "server_id" })?.value ?? ""
                completion(.success((publicToken: "oauth_complete", metadata: ["server_id": serverId])))
                return
            }

            // If we got authorization code, pass it back (for flows that need client-side exchange)
            if let code = queryItems.first(where: { $0.name == "code" })?.value {
                let state = queryItems.first(where: { $0.name == "state" })?.value ?? ""
                completion(.success((publicToken: code, metadata: ["state": state, "type": "authorization_code"])))
                return
            }

            // Unknown callback format
            completion(.failure(MCPOAuthError.invalidResponse))
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false // Allow persistent sessions for SSO

        self.authSession = session

        if !session.start() {
            completion(.failure(MCPOAuthError.sessionStartFailed))
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // This method is always called on the main thread by the system
        MainActor.assumeIsolated {
            // Return the key window
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                return window
            }
            return ASPresentationAnchor()
        }
    }
}

// MARK: - Errors

enum MCPOAuthError: LocalizedError {
    case invalidURL
    case invalidResponse
    case userCancelled
    case notImplemented
    case handlerNotFound(String)
    case sessionStartFailed
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid authorization URL"
        case .invalidResponse:
            return "Invalid response from provider"
        case .userCancelled:
            return "User cancelled authentication"
        case .notImplemented:
            return "OAuth flow not fully implemented"
        case .handlerNotFound(let type):
            return "No handler registered for type: \(type)"
        case .sessionStartFailed:
            return "Failed to start authentication session"
        case .providerError(let message):
            return "Provider error: \(message)"
        }
    }
}
