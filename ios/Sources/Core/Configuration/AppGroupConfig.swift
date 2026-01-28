import Foundation

/// Shared configuration for App Group communication between main app and Share Extension
enum AppGroupConfig {
    /// App Group identifier shared between main app and Share Extension
    /// Must be configured in Xcode under Signing & Capabilities → App Groups
    static let suiteName = "group.com.heyhouston.shared"

    /// Get shared UserDefaults instance for App Group
    static var shared: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Keys for shared data

    /// Key for storing current server URL (visible to extension)
    static let serverURLKey = "shared_server_url"

    /// Key for storing device token (visible to extension)
    static let deviceTokenKey = "shared_device_token"

    /// Key for storing user token (visible to extension)
    static let userTokenKey = "shared_user_token"

    /// Key for storing current user email (visible to extension)
    static let userEmailKey = "shared_user_email"

    /// Key for storing goals list (visible to extension for goal selection)
    static let goalsListKey = "shared_goals_list"

    /// Key for temporary pending note from Share Extension
    static let pendingNoteKey = "pendingNote"
}
