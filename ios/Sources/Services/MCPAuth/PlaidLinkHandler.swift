import Foundation
import UIKit

#if canImport(LinkKit)
import LinkKit

/// Plaid Link OAuth handler
/// Uses the Plaid Link SDK to present the bank connection flow
class PlaidLinkHandler: MCPOAuthHandlerProtocol {
    /// Shared instance for OAuth resume handling
    static let shared = PlaidLinkHandler()

    private var handler: Handler?
    private var completion: ((Result<(publicToken: String, metadata: [String: Any]), Error>) -> Void)?

    /// Continue Plaid Link OAuth flow from redirect URL
    /// Called when app receives heyhouston://plaid-oauth?oauth_state_id=...
    func continueFromRedirect(url: URL) {
        DebugLog.network("Continuing from OAuth redirect", category: "Plaid")
        guard let handler = handler else {
            DebugLog.warning("No active handler to continue", category: "Plaid")
            return
        }

        // Resume the Plaid Link flow with the redirect URL
        handler.resumeAfterTermination(from: url)
    }

    func present(
        linkToken: String,
        config: [String: Any]?,
        from presentingViewController: UIViewController,
        completion: @escaping (Result<(publicToken: String, metadata: [String: Any]), Error>) -> Void
    ) {
        self.completion = completion

        // Create Plaid Link configuration
        var linkConfiguration = LinkTokenConfiguration(
            token: linkToken,
            onSuccess: { [weak self] linkSuccess in
                self?.handleSuccess(linkSuccess)
            }
        )

        linkConfiguration.onExit = { [weak self] linkExit in
            self?.handleExit(linkExit)
        }

        linkConfiguration.onEvent = { linkEvent in
            DebugLog.network("Event: \(linkEvent.eventName)", category: "Plaid")
        }

        // Create the Plaid Link handler
        let result = Plaid.create(linkConfiguration)

        switch result {
        case .failure(let error):
            DebugLog.error("Failed to create handler", error: error, category: "Plaid")
            completion(.failure(MCPOAuthError.invalidResponse))

        case .success(let handler):
            self.handler = handler

            // Present Plaid Link
            handler.open(presentUsing: .viewController(presentingViewController))
        }
    }

    private func handleSuccess(_ success: LinkSuccess) {
        DebugLog.network("Link success - \(success.metadata.accounts.count) accounts", category: "Plaid")

        // Convert metadata to dictionary
        var metadata: [String: Any] = [:]

        // Institution is not optional in newer LinkKit versions
        let institutionMetadata = success.metadata.institution
        metadata["institution"] = [
            "name": institutionMetadata.name,
            "institution_id": institutionMetadata.id
        ]

        // Add accounts info
        let accounts = success.metadata.accounts.map { account -> [String: Any] in
            var accountDict: [String: Any] = [
                "id": account.id,
                "name": account.name,
                "subtype": String(describing: account.subtype) // Convert enum to string
            ]

            if let mask = account.mask {
                accountDict["mask"] = mask
            }

            return accountDict
        }
        metadata["accounts"] = accounts

        // Call completion with public token and metadata
        completion?(.success((publicToken: success.publicToken, metadata: metadata)))
        completion = nil
    }

    private func handleExit(_ exit: LinkExit) {
        DebugLog.network("Exit: \(exit.error?.errorMessage ?? "User cancelled")", category: "Plaid")

        if let error = exit.error {
            // Plaid returned an error
            let nsError = NSError(
                domain: "PlaidLink",
                code: 1, // Generic error code since errorCode doesn't have rawValue
                userInfo: [
                    NSLocalizedDescriptionKey: error.errorMessage,
                    "plaidErrorCode": String(describing: error.errorCode)
                ]
            )
            completion?(.failure(nsError))
        } else {
            // User cancelled
            completion?(.failure(MCPOAuthError.userCancelled))
        }

        completion = nil
    }
}

#else

/// Stub implementation when LinkKit is not available
/// This allows the app to compile without the SDK
class PlaidLinkHandler: MCPOAuthHandlerProtocol {
    static let shared = PlaidLinkHandler()

    func continueFromRedirect(url: URL) {
        DebugLog.warning("LinkKit SDK not available - cannot continue OAuth", category: "Plaid")
    }

    func present(
        linkToken: String,
        config: [String: Any]?,
        from presentingViewController: UIViewController,
        completion: @escaping (Result<(publicToken: String, metadata: [String: Any]), Error>) -> Void
    ) {
        DebugLog.warning("LinkKit SDK not available", category: "Plaid")
        completion(.failure(MCPOAuthError.notImplemented))
    }
}

#endif
