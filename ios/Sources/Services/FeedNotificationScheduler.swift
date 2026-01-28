import Foundation
import UserNotifications

/// Schedules local notifications for feed generation times
/// Used as a fallback when APNs is not configured (self-hosted deployments)
///
/// Notifications are scheduled 10 minutes after the configured feed time,
/// giving the backend time to generate the feed content.
@MainActor
final class FeedNotificationScheduler {
    static let shared = FeedNotificationScheduler()

    // Prefix for feed notification identifiers (allows selective cancellation)
    private let notificationPrefix = "feed-schedule-"

    private init() {}

    // MARK: - Scheduling

    /// Schedule local notifications based on feed schedule
    /// Cancels existing feed notifications and schedules new ones
    ///
    /// - Parameter schedule: Feed schedule from backend with periods and timezone
    func scheduleNotifications(for schedule: FeedSchedule) async {
        // First, cancel all existing feed notifications
        await cancelAllFeedNotifications()

        // Get timezone from schedule
        guard let timezone = TimeZone(identifier: schedule.timezone) else {
            print("[FeedNotificationScheduler] Invalid timezone: \(schedule.timezone)")
            return
        }

        // Schedule notification for each enabled period
        for (periodId, config) in schedule.periods where config.enabled {
            await scheduleNotification(
                period: periodId,
                time: config.time,
                timezone: timezone
            )
        }

        print("[FeedNotificationScheduler] Scheduled notifications for \(schedule.periods.filter { $0.value.enabled }.count) periods")
    }

    /// Schedule a single notification for a feed period
    private func scheduleNotification(period: String, time: String, timezone: TimeZone) async {
        // Parse hour from time string (e.g., "06:00" -> 6)
        let components = time.split(separator: ":")
        guard let hour = components.first.flatMap({ Int($0) }) else {
            print("[FeedNotificationScheduler] Invalid time format: \(time)")
            return
        }

        // Notify 5 min after scheduled time (backend generates 0-15 min early, plus generation time)
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = 5
        dateComponents.timeZone = timezone

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: period)
        content.body = notificationBody(for: period)
        content.sound = .default

        // Deep link data for navigation
        content.userInfo = [
            "type": "feed_ready",
            "url": "heyhouston://open-feed",
            "time_period": period
        ]

        // Create calendar trigger (repeats daily)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        // Create request with identifiable ID
        let identifier = "\(notificationPrefix)\(period)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[FeedNotificationScheduler] Scheduled \(period) notification for \(hour):05 \(timezone.identifier)")
        } catch {
            print("[FeedNotificationScheduler] Failed to schedule \(period): \(error)")
        }
    }

    // MARK: - Cancellation

    /// Cancel all feed-related notifications
    func cancelAllFeedNotifications() async {
        let center = UNUserNotificationCenter.current()

        // Get all pending notifications
        let pendingRequests = await center.pendingNotificationRequests()

        // Filter to only feed notifications
        let feedNotificationIds = pendingRequests
            .filter { $0.identifier.hasPrefix(notificationPrefix) }
            .map { $0.identifier }

        // Remove them
        center.removePendingNotificationRequests(withIdentifiers: feedNotificationIds)

        if !feedNotificationIds.isEmpty {
            print("[FeedNotificationScheduler] Cancelled \(feedNotificationIds.count) existing feed notifications")
        }
    }

    // MARK: - Content

    private func notificationTitle(for period: String) -> String {
        switch period {
        case "morning":
            return "Good morning"
        case "afternoon":
            return "Afternoon update"
        case "evening":
            return "Evening roundup"
        default:
            return "Feed ready"
        }
    }

    private func notificationBody(for period: String) -> String {
        switch period {
        case "morning":
            return "Your morning feed is ready with fresh insights"
        case "afternoon":
            return "New discoveries and reflections await"
        case "evening":
            return "Wind down with your evening feed"
        default:
            return "New insights and discoveries are ready"
        }
    }
}
