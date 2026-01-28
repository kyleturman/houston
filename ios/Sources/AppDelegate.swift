import UIKit
import UserNotifications

/// AppDelegate for handling app lifecycle and local notifications
/// Implements UNUserNotificationCenterDelegate to receive and route notification events
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // MARK: - UIApplicationDelegate

    /// Called when app finishes launching
    /// Sets up notification center delegate
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set ourselves as notification delegate to handle all notification events
        UNUserNotificationCenter.current().delegate = self

        print("[AppDelegate] Initialized with notification center delegate")
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when user taps on a notification (app in background or terminated)
    /// Routes notification data to NotificationManager for deep link handling
    ///
    /// NOTE: Using completion handler version instead of async version to avoid
    /// UIKit assertion failures during cold launch. The async version with
    /// `await MainActor.run` causes timing issues with UIKit's internal state.
    /// Marked nonisolated since UNUserNotificationCenterDelegate can call from any thread.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("[AppDelegate] User tapped notification: \(response.notification.request.identifier)")

        // Extract and convert userInfo to Sendable types
        let content = response.notification.request.content
        let userInfo = content.userInfo.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }

        // Forward to NotificationManager on main actor for deep link routing
        // Use Task to dispatch without blocking
        Task { @MainActor in
            NotificationManager.shared.handleNotificationTap(userInfo: userInfo)
        }

        // Call completion handler immediately
        completionHandler()
    }

    /// Called when notification arrives while app is in foreground
    /// Determines how to present the notification
    /// Marked nonisolated since UNUserNotificationCenterDelegate can call from any thread.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("[AppDelegate] Notification arrived in foreground: \(notification.request.content.title)")

        // Show banner, play sound, and update badge even when app is open
        completionHandler([.banner, .sound, .badge])
    }
}
