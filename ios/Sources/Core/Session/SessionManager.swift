import Foundation
import Observation

@MainActor
@Observable
final class SessionManager {
    enum AppPhase {
        case loading  // Initial state while loading persisted data
        case landing
        case onboarding
        case main
    }

    var phase: AppPhase = .loading
    var signInError: String? = nil

    /// Indicates that the server is unreachable (network error, not auth failure)
    /// When true, we keep the user's credentials and show a reconnection UI
    var serverUnavailable: Bool = false

    /// Set to true while attempting to reconnect to the server
    var isRetryingConnection: Bool = false

    /// Flag to suppress didSet side effects during initial load
    /// This prevents wasteful re-persisting and premature phase updates
    private var isLoading = false

    // Current server selection and derived values
    var deviceToken: String? {
        didSet {
            guard !isLoading else { return }
            persistDeviceToken()
            syncToAppGroup()
        }
    }
    var serverURL: URL? {
        didSet {
            guard !isLoading else { return }
            guard oldValue != serverURL else { return }

            print("[SessionManager] 🔄 Server URL changed from \(oldValue?.absoluteString ?? "nil") to \(serverURL?.absoluteString ?? "nil")")

            persistServerURL()
            // When server changes, load stored data for that server
            loadUserTokenForCurrentServer()
            loadDeviceTokenForCurrentServer()
            loadCurrentUserEmailForCurrentServer()
            loadCurrentUserNameForCurrentServer()
            loadOnboardingCompletedForCurrentServer()
            loadEmailEnabledForCurrentServer()

            updatePhaseForCurrentState()
            syncToAppGroup()
        }
    }
    var userToken: String? {
        didSet {
            guard !isLoading else { return }
            guard oldValue != userToken else { return }

            if userToken != nil {
                print("[SessionManager] ✅ User token updated (exists)")
            } else {
                print("[SessionManager] ⚠️ User token cleared")
            }

            persistUserToken()
            updatePhaseForCurrentState()
            syncToAppGroup()
        }
    }
    var onboardingCompleted: Bool = false {
        didSet {
            guard !isLoading else { return }
            guard oldValue != onboardingCompleted else { return }

            print("[SessionManager] 🎓 Onboarding completed changed from \(oldValue) to \(onboardingCompleted)")
            persistOnboardingCompleted()
            updatePhaseForCurrentState()
        }
    }

    // Current user display info
    var currentUserEmail: String? {
        didSet {
            guard !isLoading else { return }
            persistCurrentUserEmailForCurrentServer()
        }
    }
    var currentUserName: String? {
        didSet {
            guard !isLoading else { return }
            persistCurrentUserNameForCurrentServer()
        }
    }

    /// Whether the server has email configured (for magic link sign-in)
    /// When false, users should use invite codes instead of "resend sign-in link"
    var emailEnabled: Bool = true {
        didSet {
            guard !isLoading else { return }
            persistEmailEnabledForCurrentServer()
        }
    }

    // Multi-server support
    var servers: [ServerProfile] = [] {
        didSet {
            guard !isLoading else { return }
            // Safeguard: Don't persist empty servers list if we had servers before
            // This prevents accidental data loss from race conditions or Keychain access issues
            if servers.isEmpty && !oldValue.isEmpty {
                print("[SessionManager] ⚠️ WARNING: Attempting to clear servers list (had \(oldValue.count) servers)")
                print("[SessionManager] This may be unintentional - check call stack")
                // Still persist for intentional sign-outs, but log for debugging
            }
            persistServersList()
        }
    }
    var selectedServerId: UUID? {
        didSet {
            guard !isLoading else { return }
            persistSelectedServerId()
            updatePhaseForCurrentState()
        }
    }

    var currentServerName: String? {
        guard let sel = selectedServerId, let p = servers.first(where: { $0.id == sel }) else { return nil }
        return p.name
    }

    /// Initialize SessionManager
    /// - Parameter skipLoad: If true, skips loading persisted data. Use for placeholder instances
    ///   that will be replaced with the real session via Environment.
    init(skipLoad: Bool = false) {
        if !skipLoad {
            loadPersisted()
        }
    }

    func routeToLanding() { phase = .landing }
    func routeToOnboarding() { phase = .onboarding }
    func routeToMain() { phase = .main }

    func setServer(url: URL) {
        serverURL = url
    }

    func signOutDevice() {
        if let server = serverURL?.absoluteString {
            KeychainHelper.delete(key: SessionManager.deviceTokenKey(for: server))
        }
        deviceToken = nil
        phase = .landing
    }

    func signOutUser() {
        guard let server = serverURL?.absoluteString else { return }

        // Clear all stored data for this server
        KeychainHelper.delete(key: SessionManager.deviceTokenKey(for: server))
        KeychainHelper.delete(key: SessionManager.userTokenKey(for: server))
        UserDefaults.standard.removeObject(forKey: SessionManager.userEmailKey(for: server))
        UserDefaults.standard.removeObject(forKey: SessionManager.userNameKey(for: server))
        UserDefaults.standard.removeObject(forKey: SessionManager.onboardingCompletedKey(for: server))

        deviceToken = nil
        userToken = nil
        currentUserEmail = nil
        currentUserName = nil

        // Clear server unavailable state
        serverUnavailable = false
        isRetryingConnection = false

        // Clear API cache on logout
        makeClient()?.clearAllCache()

        // Remove the current server from the list
        // Since users only add servers via magic link, signing out means they're done with this server
        if let serverId = selectedServerId {
            servers.removeAll { $0.id == serverId }
            selectedServerId = nil
            serverURL = nil
        }

        // This will automatically route to landing since servers is now empty
        updatePhaseForCurrentState()
    }

    /// Create an authenticated API client
    /// Returns nil if server URL is not configured
    func makeClient() -> APIClient? {
        guard let baseURL = serverURL else { return nil }
        return APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { self.deviceToken },
            userTokenProvider: { self.userToken }
        )
    }

    // Attempt to refresh the user's JWT token
    func refreshUserToken() async -> Bool {
        guard let client = makeClient() else { return false }

        do {
            let response = try await client.refreshToken()
            // Update the user token with the fresh one
            self.userToken = response.user_token
            self.onboardingCompleted = response.onboarding_completed

            // Also update user info from refresh response
            self.currentUserEmail = response.email

            // Update email enabled status (defaults to true if not present for backwards compatibility)
            self.emailEnabled = response.email_enabled ?? true

            // Server is reachable - clear any previous unavailable state
            self.serverUnavailable = false

            print("[SessionManager] Token refreshed successfully - new expiry in 90 days")
            return true
        } catch {
            // Distinguish between network errors and auth errors
            if isNetworkError(error) {
                // Network error - server is unavailable, keep credentials
                print("[SessionManager] Token refresh failed due to network error: \(error)")
                self.serverUnavailable = true
                // Don't clear tokens - user can retry when server is back
                return false
            } else {
                // Auth error (401, token expired, etc.) - clear tokens
                print("[SessionManager] Token refresh failed due to auth error: \(error)")
                self.serverUnavailable = false
                clearTokensButKeepServer()
                return false
            }
        }
    }

    /// Check if an error is a network/connectivity error (server unavailable)
    /// vs an authentication error (token expired/invalid)
    ///
    /// IMPORTANT: Be conservative here - it's better to show the "server unavailable" overlay
    /// and let the user retry than to sign them out unexpectedly.
    /// Only treat errors as "auth errors" when we're CERTAIN the server responded with 401/403.
    private func isNetworkError(_ error: Error) -> Bool {
        // Check for URLError network-related codes
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed,
                 .secureConnectionFailed,
                 .resourceUnavailable,
                 .badServerResponse,
                 .zeroByteResource:
                return true
            default:
                // For any other URLError, log it and treat as network error to be safe
                print("[SessionManager] Unknown URLError code: \(urlError.code.rawValue) - treating as network error")
                return true
            }
        }

        // Check for APIClient errors
        if let apiError = error as? APIClient.APIError {
            switch apiError {
            case .requestFailed(let statusCode, _):
                // nil status code means request never reached server (network error)
                if statusCode == nil {
                    return true
                }
                // 5xx errors indicate server problems (gateway timeout, bad gateway, etc.)
                // These should be treated as "server unavailable", not auth errors
                if let code = statusCode, code >= 500 {
                    print("[SessionManager] Server returned \(code) - treating as server unavailable")
                    return true
                }
                // Only 401/403 are definitive auth errors
                // Other 4xx errors (like 404, 400) could be server misconfiguration
                if let code = statusCode, (code == 401 || code == 403) {
                    return false
                }
                // For other status codes, be conservative and treat as network error
                print("[SessionManager] Unexpected status code \(statusCode ?? -1) - treating as network error")
                return true
            case .decodingFailed:
                // Decoding errors could indicate server returning garbage (overloaded/restarting)
                print("[SessionManager] Decoding failed - treating as network error")
                return true
            case .invalidURL:
                // This shouldn't happen for refresh, but treat as auth error since it's our bug
                return false
            }
        }

        // For any unknown error type, be conservative and treat as network error
        // This prevents unexpected sign-outs from wrapped errors or new error types
        print("[SessionManager] Unknown error type: \(type(of: error)) - \(error.localizedDescription) - treating as network error")
        return true
    }

    /// Retry connecting to the server
    /// Called when user taps "Retry" on the server unavailable screen
    func retryConnection() async {
        guard !isRetryingConnection else { return }

        isRetryingConnection = true
        defer { isRetryingConnection = false }

        print("[SessionManager] Retrying connection to server...")

        let success = await refreshUserToken()

        if success {
            print("[SessionManager] Reconnection successful!")
            ToastManager.shared.show("Connected to server", type: .success)
            updatePhaseForCurrentState()
        } else if serverUnavailable {
            print("[SessionManager] Server still unavailable")
            ToastManager.shared.show("Server unavailable", type: .error)
        } else {
            // Auth error - tokens were cleared, user needs to re-authenticate
            print("[SessionManager] Re-authentication required")
        }
    }

    /// Clear user tokens without deleting the server profile
    /// Used when token refresh fails - allows re-authentication via magic link
    private func clearTokensButKeepServer() {
        guard let server = serverURL?.absoluteString else { return }

        print("[SessionManager] 🧹 Clearing tokens but keeping server profile for re-authentication")

        // Clear tokens from Keychain
        KeychainHelper.delete(key: SessionManager.deviceTokenKey(for: server))
        KeychainHelper.delete(key: SessionManager.userTokenKey(for: server))

        // Clear in-memory tokens
        deviceToken = nil
        userToken = nil

        // Clear API cache
        makeClient()?.clearAllCache()

        // Server profile stays intact - user can re-authenticate
        updatePhaseForCurrentState()
    }

    private func loadPersisted() {
        // Suppress didSet side effects during load to avoid:
        // - Re-persisting data we just read
        // - Premature phase updates
        // - Multiple app group syncs
        isLoading = true
        defer {
            isLoading = false
            // Single sync to app group after all data is loaded
            syncToAppGroup()
        }

        // Load servers list
        if let data = UserDefaults.standard.data(forKey: "servers_list") {
            do {
                let decoded = try JSONDecoder().decode([ServerProfile].self, from: data)
                self.servers = decoded
                print("[SessionManager] ✅ Loaded \(decoded.count) server(s) from UserDefaults")
            } catch {
                print("[SessionManager] ❌ Failed to decode servers list: \(error)")
                print("[SessionManager] Raw data length: \(data.count) bytes")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[SessionManager] Raw JSON: \(jsonString)")
                }
            }
        } else {
            print("[SessionManager] ⚠️ No servers_list found in UserDefaults")
        }
        // Migration from legacy single server_url OR recovery if servers got wiped
        if servers.isEmpty {
            // Try to recover from legacy server_url key
            if let urlStr = UserDefaults.standard.string(forKey: "server_url"), let url = URL(string: urlStr) {
                let defaultName = url.host ?? "My Server"

                // If we have a selectedServerId, reuse it (recovery scenario)
                // Otherwise create new ID (migration scenario)
                let profile: ServerProfile
                if let existingId = selectedServerId {
                    profile = ServerProfile(id: existingId, name: defaultName, baseURL: url)
                    print("[SessionManager] 🔧 Recovered server profile from legacy URL with existing ID")
                } else {
                    profile = ServerProfile(name: defaultName, baseURL: url)
                    self.selectedServerId = profile.id
                    print("[SessionManager] 📦 Migrated server from legacy URL")
                }

                self.servers = [profile]
                self.serverURL = url
            } else {
                print("[SessionManager] ⚠️ No servers found and no legacy URL to migrate from")
            }
        }
        // Load selected server id
        if let selStr = UserDefaults.standard.string(forKey: "selected_server_id"), let sel = UUID(uuidString: selStr) {
            self.selectedServerId = sel
        }
        // If selected id maps to a server, set serverURL
        if let sel = selectedServerId, let profile = servers.first(where: { $0.id == sel }), let url = profile.baseURL {
            self.serverURL = url
        }
        // Otherwise, if we have at least one server profile, default to first
        if serverURL == nil, let first = servers.first, let url = first.baseURL {
            self.selectedServerId = first.id
            self.serverURL = url
        }
        // Migration: if legacy device token exists under global key, move it to namespaced per-server key
        if let legacyData = KeychainHelper.load(key: "device_token"),
           let legacyDeviceToken = String(data: legacyData, encoding: .utf8),
           let server = serverURL?.absoluteString {
            // Only set if not already present in the new location
            if KeychainHelper.load(key: SessionManager.deviceTokenKey(for: server)) == nil {
                try? KeychainHelper.save(key: SessionManager.deviceTokenKey(for: server), data: Data(legacyDeviceToken.utf8))
            }
        }
        loadUserTokenForCurrentServer()
        loadDeviceTokenForCurrentServer()
        loadCurrentUserEmailForCurrentServer()
        loadCurrentUserNameForCurrentServer()
        loadOnboardingCompletedForCurrentServer()
        loadEmailEnabledForCurrentServer()

        print("[SessionManager] 📦 Loaded from persistence:")
        print("  - servers: \(servers.count)")
        print("  - selectedServerId: \(selectedServerId?.uuidString ?? "nil")")
        print("  - serverURL: \(serverURL?.absoluteString ?? "nil")")
        print("  - userToken: \(userToken != nil ? "exists" : "nil")")
        print("  - deviceToken: \(deviceToken != nil ? "exists" : "nil")")
        print("  - onboardingCompleted: \(onboardingCompleted)")
        print("  - emailEnabled: \(emailEnabled)")

        // DON'T delete servers just because token load failed - Keychain could be temporarily inaccessible
        // Instead, let user re-authenticate via magic link if needed
        // Only route to landing page if no token, but keep the server profile intact

        updatePhaseForCurrentState()

        // Proactively refresh user token on app launch to ensure long-term sign-in persistence
        // This prevents the token from expiring silently and causing unexpected sign-outs
        if userToken != nil {
            Task {
                await validateAndRefreshTokenOnLaunch()
            }
        }
    }

    /// Validate and refresh the user token on app launch
    /// This ensures the stored token is still valid and refreshes it to extend the session
    /// Called automatically when app loads persisted session data
    private func validateAndRefreshTokenOnLaunch() async {
        print("[SessionManager] Validating and refreshing token on app launch...")

        let success = await refreshUserToken()

        if success {
            print("[SessionManager] ✅ Token refreshed successfully on launch - session extended")
        } else if serverUnavailable {
            print("[SessionManager] ⚠️ Server unavailable on launch - keeping credentials for retry")
            // Show toast to inform user about server unavailability
            ToastManager.shared.show("Server unavailable - tap to retry", type: .warning, duration: 5.0)
        } else {
            print("[SessionManager] ⚠️ Token refresh failed on launch - user needs to re-authenticate")
            // refreshUserToken() already handles clearing tokens on auth failure
        }
    }

    private func persistDeviceToken() {
        guard let server = serverURL?.absoluteString else { return }
        if let token = deviceToken {
            try? KeychainHelper.save(key: SessionManager.deviceTokenKey(for: server), data: Data(token.utf8))
        }
    }

    private func persistServerURL() {
        if let url = serverURL {
            UserDefaults.standard.set(url.absoluteString, forKey: "server_url")
        } else {
            // Clear legacy single-server key so migration does not resurrect deleted servers
            UserDefaults.standard.removeObject(forKey: "server_url")
        }
    }

    private func persistUserToken() {
        guard let server = serverURL?.absoluteString else { return }
        if let token = userToken {
            try? KeychainHelper.save(key: SessionManager.userTokenKey(for: server), data: Data(token.utf8))
        }
    }

    private func loadUserTokenForCurrentServer() {
        guard let server = serverURL?.absoluteString else {
            print("[SessionManager] ⚠️ loadUserToken: No server URL, clearing user token")
            self.userToken = nil
            return
        }

        if let data = KeychainHelper.load(key: SessionManager.userTokenKey(for: server)) {
            self.userToken = String(data: data, encoding: .utf8)
            print("[SessionManager] 🔑 Loaded user token from Keychain for server: \(server)")
        } else {
            self.userToken = nil
            print("[SessionManager] ⚠️ No user token found in Keychain for server: \(server)")
        }
    }

    private func loadDeviceTokenForCurrentServer() {
        guard let server = serverURL?.absoluteString else { self.deviceToken = nil; return }
        if let data = KeychainHelper.load(key: SessionManager.deviceTokenKey(for: server)) {
            self.deviceToken = String(data: data, encoding: .utf8)
        } else {
            self.deviceToken = nil
        }
    }

    // Complete onboarding by calling API to update backend
    func completeOnboarding() async throws {
        guard let client = makeClient() else {
            throw NSError(domain: "SessionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API client available"])
        }
        _ = try await client.completeOnboarding()
    }

    private func persistCurrentUserEmailForCurrentServer() {
        guard let server = serverURL?.absoluteString else { return }
        UserDefaults.standard.set(currentUserEmail, forKey: SessionManager.userEmailKey(for: server))
    }

    private func loadCurrentUserEmailForCurrentServer() {
        guard let server = serverURL?.absoluteString else { self.currentUserEmail = nil; return }
        self.currentUserEmail = UserDefaults.standard.string(forKey: SessionManager.userEmailKey(for: server))
    }

    private func persistCurrentUserNameForCurrentServer() {
        guard let server = serverURL?.absoluteString else { return }
        UserDefaults.standard.set(currentUserName, forKey: SessionManager.userNameKey(for: server))
    }

    private func loadCurrentUserNameForCurrentServer() {
        guard let server = serverURL?.absoluteString else { self.currentUserName = nil; return }
        self.currentUserName = UserDefaults.standard.string(forKey: SessionManager.userNameKey(for: server))
    }

    private func persistOnboardingCompleted() {
        guard let server = serverURL?.absoluteString else { return }
        UserDefaults.standard.set(onboardingCompleted, forKey: SessionManager.onboardingCompletedKey(for: server))
    }

    private func loadOnboardingCompletedForCurrentServer() {
        guard let server = serverURL?.absoluteString else { self.onboardingCompleted = false; return }
        self.onboardingCompleted = UserDefaults.standard.bool(forKey: SessionManager.onboardingCompletedKey(for: server))
    }

    private func persistEmailEnabledForCurrentServer() {
        guard let server = serverURL?.absoluteString else { return }
        UserDefaults.standard.set(emailEnabled, forKey: SessionManager.emailEnabledKey(for: server))
    }

    private func loadEmailEnabledForCurrentServer() {
        guard let server = serverURL?.absoluteString else { self.emailEnabled = true; return }
        // Default to true for backwards compatibility with servers that don't send this field
        let key = SessionManager.emailEnabledKey(for: server)
        if UserDefaults.standard.object(forKey: key) != nil {
            self.emailEnabled = UserDefaults.standard.bool(forKey: key)
        } else {
            self.emailEnabled = true
        }
    }

    private func persistServersList() {
        do {
            let data = try JSONEncoder().encode(servers)
            UserDefaults.standard.set(data, forKey: "servers_list")
            UserDefaults.standard.synchronize() // Force immediate write to disk
            print("[SessionManager] 💾 Persisted \(servers.count) server(s) to UserDefaults (\(data.count) bytes)")

            // Verify it was written correctly
            if let verified = UserDefaults.standard.data(forKey: "servers_list") {
                print("[SessionManager] ✅ Verified write: \(verified.count) bytes")
            } else {
                print("[SessionManager] ❌ WARNING: Failed to verify servers_list write!")
            }
        } catch {
            print("[SessionManager] ❌ Failed to encode servers list: \(error)")
        }
    }

    private func persistSelectedServerId() {
        if let sel = selectedServerId { UserDefaults.standard.set(sel.uuidString, forKey: "selected_server_id") }
    }

    private static func userTokenKey(for server: String) -> String { "user_token::" + server }
    private static func deviceTokenKey(for server: String) -> String { "device_token::" + server }
    private static func userEmailKey(for server: String) -> String { "user_email::" + server }
    private static func userNameKey(for server: String) -> String { "user_name::" + server }
    private static func onboardingCompletedKey(for server: String) -> String { "onboarding_completed::" + server }
    private static func emailEnabledKey(for server: String) -> String { "email_enabled::" + server }

    // MARK: - App Group Sync for Share Extension

    /// Sync current session state to App Group so Share Extension can access it
    private func syncToAppGroup() {
        guard let appGroup = AppGroupConfig.shared else {
            print("[SessionManager] Warning: Could not access App Group")
            return
        }

        // Sync server URL
        if let url = serverURL {
            appGroup.set(url.absoluteString, forKey: AppGroupConfig.serverURLKey)
        } else {
            appGroup.removeObject(forKey: AppGroupConfig.serverURLKey)
        }

        // Sync tokens
        if let token = deviceToken {
            appGroup.set(token, forKey: AppGroupConfig.deviceTokenKey)
        } else {
            appGroup.removeObject(forKey: AppGroupConfig.deviceTokenKey)
        }

        if let token = userToken {
            appGroup.set(token, forKey: AppGroupConfig.userTokenKey)
        } else {
            appGroup.removeObject(forKey: AppGroupConfig.userTokenKey)
        }

        // Sync user email
        if let email = currentUserEmail {
            appGroup.set(email, forKey: AppGroupConfig.userEmailKey)
        } else {
            appGroup.removeObject(forKey: AppGroupConfig.userEmailKey)
        }

        appGroup.synchronize()
    }

    // MARK: - Server Management
    func addServer(name: String, url: URL, email: String? = nil) {
        let profile = ServerProfile(name: name, baseURL: url, email: email)
        servers.append(profile)
        selectedServerId = profile.id
        serverURL = url
        updatePhaseForCurrentState()
    }

    func renameServer(id: UUID, newName: String) {
        if let idx = servers.firstIndex(where: { $0.id == id }) {
            servers[idx].name = newName
        }
    }

    func removeServer(id: UUID) {
        // Capture URL string to purge stored data
        let removedProfile = servers.first(where: { $0.id == id })
        let removedURLString = removedProfile?.baseURL?.absoluteString
        // If removing current server, clear selection and tokens in memory
        if selectedServerId == id { selectedServerId = nil; serverURL = nil; deviceToken = nil; userToken = nil }
        // Remove from list
        servers.removeAll { $0.id == id }
        // Purge all persisted items for this server
        if let server = removedURLString {
            KeychainHelper.delete(key: SessionManager.deviceTokenKey(for: server))
            KeychainHelper.delete(key: SessionManager.userTokenKey(for: server))
            UserDefaults.standard.removeObject(forKey: SessionManager.userEmailKey(for: server))
            UserDefaults.standard.removeObject(forKey: SessionManager.userNameKey(for: server))
            UserDefaults.standard.removeObject(forKey: SessionManager.onboardingCompletedKey(for: server))
        }
        // Auto-select first if available
        if selectedServerId == nil, let first = servers.first, let url = first.baseURL {
            selectedServerId = first.id
            serverURL = url
        }
        updatePhaseForCurrentState()
    }

    func selectServer(id: UUID) {
        guard let profile = servers.first(where: { $0.id == id }), let url = profile.baseURL else { return }
        selectedServerId = id
        serverURL = url
        updatePhaseForCurrentState()
    }

    private func updatePhaseForCurrentState() {
        let oldPhase = phase

        if servers.isEmpty {
            print("[SessionManager] 📍 Phase: landing (no servers)")
            phase = .landing
            return
        }
        // Ensure we have a valid server URL - without it, we can't make API calls
        if serverURL == nil {
            print("[SessionManager] 📍 Phase: landing (no valid server URL)")
            phase = .landing
            return
        }
        // Have at least one server selected
        if userToken == nil {
            // No user token yet - stay at landing
            // User will authenticate via magic link
            print("[SessionManager] 📍 Phase: landing (no user token)")
            phase = .landing
            return
        }
        if !onboardingCompleted {
            print("[SessionManager] 📍 Phase: onboarding (onboardingCompleted=false)")
            phase = .onboarding
            return
        }

        print("[SessionManager] 📍 Phase: main (all requirements met)")
        phase = .main

        if oldPhase != phase {
            print("[SessionManager] 🔄 Phase transition: \(oldPhase) → \(phase)")
        }
    }
}


