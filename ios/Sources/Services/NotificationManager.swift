import Foundation
import UserNotifications
import Observation
@preconcurrency import Combine
import UIKit

/// Manages local notifications for Houston
/// Handles authorization and deep link routing
@MainActor
@Observable
final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()

    // MARK: - State

    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var hasRequestedPermission = false

    // Deep link publisher for routing
    let deepLinkPublisher = PassthroughSubject<DeepLink, Never>()

    // Pending deep link for cold-launch scenarios
    // Stored when notification arrives before view is ready
    var pendingDeepLink: DeepLink?

    private init() {
        Task {
            await updateAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Request notification permission from user
    /// Returns true if granted, false if denied
    func requestAuthorization() async throws -> Bool {
        hasRequestedPermission = true

        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: options)

        await updateAuthorizationStatus()

        if granted {
            print("[NotificationManager] Authorization granted")
        }

        return granted
    }

    /// Update current authorization status
    func updateAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Notification Tap Handling

    /// Handle user tapping on a notification
    /// Parses deep link data and stores for navigation
    /// Called from AppDelegate when user taps notification
    func handleNotificationTap(userInfo: [String: String]) {
        print("[NotificationManager] Handling notification tap: \(userInfo)")

        guard let type = userInfo["type"],
              let urlString = userInfo["url"],
              let url = URL(string: urlString) else {
            print("[NotificationManager] Invalid notification data")
            return
        }

        let deepLink = DeepLink(type: type, url: url, data: userInfo)

        // Store as pending for cold-launch scenarios
        pendingDeepLink = deepLink

        // Also publish for warm-launch scenarios where subscriber exists
        deepLinkPublisher.send(deepLink)
    }

    /// Process any pending deep link (call after view is ready)
    /// Returns and clears the pending deep link if one exists
    func consumePendingDeepLink() -> DeepLink? {
        let deepLink = pendingDeepLink
        pendingDeepLink = nil
        return deepLink
    }

    // MARK: - Local Notifications

    /// Schedule a local notification to be displayed immediately
    ///
    /// - Parameters:
    ///   - title: Notification title
    ///   - body: Notification body text
    ///   - data: Custom data for deep linking
    func scheduleLocalNotification(title: String, body: String, data: [String: String]) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Convert data to userInfo format
        content.userInfo = data

        // Immediate trigger (fire in 0.1 seconds)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Unique identifier for each notification
        let identifier = UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[NotificationManager] Scheduled local notification: \(title)")
        } catch {
            print("[NotificationManager] Failed to schedule notification: \(error)")
        }
    }

    // MARK: - Badge Management

    /// Clear app icon badge
    func clearBadge() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Set app icon badge number
    func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
