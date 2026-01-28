import Foundation
import SwiftUI
import UIKit

/// Deep link model from notifications
/// This matches the DeepLink struct in NotificationManager
struct DeepLink: Sendable {
    let type: String
    let url: URL
    let data: [String: String]

    var timePeriod: String? { data["time_period"] }
}

enum DeepLinkHandler {
    /// Handle URL-based deep links (from share extension, magic links, etc.)
    static func handle(url: URL, session: SessionManager) {
        let registeredScheme = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])?
            .first?["CFBundleURLSchemes"] as? [String]
        let scheme = registeredScheme?.first?.lowercased()
        guard let schemeLower = scheme, url.scheme?.lowercased() == schemeLower else { return }

        let host = url.host?.lowercased()

        // Handle add-note from Share Extension (legacy - now saves directly in extension)
        if host == "add-note" {
            handleAddNote()
            return
        }

        // Handle open-goal from Share Extension
        if host == "open-goal" {
            handleOpenGoal(url: url)
            return
        }

        // Handle open-history from Share Extension
        if host == "open-history" {
            handleOpenHistory()
            return
        }

        // Handle Plaid OAuth redirect
        if host == "plaid-oauth" {
            handlePlaidOAuthRedirect(url: url)
            return
        }

        // Handle sign-in (supports both magic links and invite tokens)
        guard host == "signin" else { return }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).compactMap { item in
            item.value.map { (item.name.lowercased(), $0) }
        })
        guard let token = q["token"], let serverStr = q["url"], let serverURL = URL(string: serverStr) else { return }
        let name = q["name"] ?? (URL(string: serverStr)?.host ?? "My Server")
        let email = q["email"]?.lowercased()
        let type = q["type"] ?? "magic"  // Default to magic for backwards compatibility

        Task {
            let api = APIClient(baseURL: serverURL, deviceTokenProvider: { nil })
            // Verify server is reachable before attempting to claim or adding it to the list
            do {
                _ = try await api.up()
            } catch {
                await MainActor.run {
                    session.signInError = "Cannot reach server at \(serverURL.host ?? serverURL.absoluteString). Make sure your device is on the same network or that your tunnel is active."
                    session.routeToLanding()
                }
                return
            }
            await MainActor.run {
                // Clear any previous errors
                session.signInError = nil
                // Now that reachability is confirmed, add/select server so tokens persist correctly
                session.addServer(name: name, url: serverURL, email: email)
                if let email = email { session.currentUserEmail = email }
            }
            do {
                // Use appropriate claim method based on link type
                let response: MagicClaimResponse
                if type == "invite", let email = email {
                    response = try await api.claimInviteToken(email: email, token: token)
                } else {
                    response = try await api.claimMagicLink(token: token)
                }
                await MainActor.run {
                    // Update server name from response if available (more reliable than deep link param)
                    if let serverName = response.server_name, let serverId = session.selectedServerId {
                        session.renameServer(id: serverId, newName: serverName)
                    }
                    session.deviceToken = response.device_token
                    session.userToken = response.user_token
                    session.onboardingCompleted = response.onboarding_completed
                    // Update email enabled status (defaults to true for backwards compatibility)
                    session.emailEnabled = response.email_enabled ?? true
                    // SessionManager will auto-route to onboarding or main based on onboarding_completed
                }
            } catch {
                await MainActor.run {
                    let errorMsg = type == "invite"
                        ? "Invalid or expired invite code. Please request a new one from your server administrator."
                        : "We couldn't complete sign-in with this link. Please request a new link and try again."
                    session.signInError = errorMsg
                    session.routeToLanding()
                }
            }
        }
    }

    private static func handleAddNote() {
        // Retrieve pending note from App Group UserDefaults
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.heyhouston.shared"),
              let pendingNote = appGroupDefaults.dictionary(forKey: "pendingNote") else {
            print("[DeepLinkHandler] No pending note found in App Group")
            return
        }

        // Extract URL or text from pending note
        let sharedURL = pendingNote["url"] as? String
        let sharedText = pendingNote["content"] as? String

        // Clear the pending note
        appGroupDefaults.removeObject(forKey: "pendingNote")
        appGroupDefaults.synchronize()

        // Post notification with shared content
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowNoteComposeWithSharedContent"),
            object: nil,
            userInfo: ["url": sharedURL as Any, "text": sharedText as Any]
        )
    }

    private static func handleOpenGoal(url: URL) {
        // Extract goal ID from query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let goalId = queryItems.first(where: { $0.name == "id" })?.value else {
            print("[DeepLinkHandler] Missing goal ID in open-goal URL")
            return
        }

        handleOpenGoal(goalId: goalId)
    }

    private static func handleOpenHistory() {
        // Post notification to navigate to history
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToHistory"),
            object: nil,
            userInfo: nil
        )
    }

    private static func handlePlaidOAuthRedirect(url: URL) {
        print("[DeepLinkHandler] Handling Plaid OAuth redirect: \(url)")
        // Resume the Plaid Link flow with the redirect URL
        Task { @MainActor in
            PlaidLinkHandler.shared.continueFromRedirect(url: url)
        }
    }

    // MARK: - Notification Deep Links

    /// Handle deep links from push notifications
    /// Routes based on notification type - always navigates to home/feed
    /// Must be called on main thread
    @MainActor
    static func handleNotification(deepLink: DeepLink) {
        print("[DeepLinkHandler] Handling notification deep link: type=\(deepLink.type)")

        // All notifications navigate to home screen (feed)
        // This is the expected behavior per user requirements
        handleOpenFeed(timePeriod: deepLink.timePeriod)
    }

    private static func handleOpenFeed(timePeriod: String?) {
        // Post notification to navigate to feed
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToFeed"),
            object: nil,
            userInfo: timePeriod.map { ["timePeriod": $0] }
        )
    }

    private static func handleOpenGoal(goalId: String) {
        // Post notification to navigate to goal
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToGoal"),
            object: nil,
            userInfo: ["goalId": goalId]
        )
    }
}
