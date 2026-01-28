import SwiftUI
import UIKit
import Combine
import UserNotifications

@main
struct HoustonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var session = SessionManager()
    @State private var themeManager = ThemeManager.shared
    @State private var stateManager = StateManager.shared
    @State private var networkMonitor = NetworkMonitor()
    @State private var notificationManager = NotificationManager.shared
    @State private var keyboardInsetManager = KeyboardInsetManager()
    @State private var rememberedUserStore = RememberedUserStore()

    init() {
        // Validate color system at app startup - this will crash the app at launch
        // if there are any inconsistencies in the colors.json file
        ColorSystemValidation.validateAtStartup()

        // Configure global appearance for system UI components
        configureAppearance()
    }

    /// Configure UIKit appearance for navigation bars and other system components
    private func configureAppearance() {
        // Navigation bar title fonts
        let titleFont = UIFont(name: AppTitleFontFamily, size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let largeTitleFont = UIFont(name: AppTitleFontFamily, size: 34) ?? .systemFont(ofSize: 34, weight: .bold)

        // Standard appearance (inline title)
        let standardAppearance = UINavigationBarAppearance()
        standardAppearance.configureWithDefaultBackground()
        standardAppearance.titleTextAttributes = [.font: titleFont]
        standardAppearance.largeTitleTextAttributes = [.font: largeTitleFont]

        // Scroll edge appearance (when content is at top)
        let scrollEdgeAppearance = UINavigationBarAppearance()
        scrollEdgeAppearance.configureWithTransparentBackground()
        scrollEdgeAppearance.titleTextAttributes = [.font: titleFont]
        scrollEdgeAppearance.largeTitleTextAttributes = [.font: largeTitleFont]

        UINavigationBar.appearance().standardAppearance = standardAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdgeAppearance
        UINavigationBar.appearance().compactAppearance = standardAppearance
    }

    var body: some Scene {
        WindowGroup {
            SystemAwareRootView()
                .environment(session)
                .environment(themeManager)
                .environment(stateManager)
                .environment(networkMonitor)
                .environment(notificationManager)
                .environment(keyboardInsetManager)
                .environment(rememberedUserStore)
                // If user is not following system appearance, force the app's
                // preferred color scheme so dynamic colors and views update immediately.
                .preferredColorScheme(themeManager.effectiveColorScheme)
                .onOpenURL { url in
                    DeepLinkHandler.handle(url: url, session: session)
                }
                .onReceive(notificationManager.deepLinkPublisher) { deepLink in
                    // Handle deep links from notifications (warm launch)
                    DeepLinkHandler.handleNotification(deepLink: deepLink)
                }
                .onAppear {
                    // Check for pending deep link (cold launch from notification)
                    if let pendingDeepLink = notificationManager.consumePendingDeepLink() {
                        // Delay slightly to ensure navigation is ready
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            DeepLinkHandler.handleNotification(deepLink: pendingDeepLink)
                        }
                    }

                    // Connect NetworkMonitor to StateManager for coordination
                    stateManager.setNetworkMonitor(networkMonitor)

                    // Connect StateManager to global SSE stream for real-time updates
                    stateManager.connect(session: session)

                    // Request notification permissions if not already requested
                    if !notificationManager.hasRequestedPermission {
                        Task {
                            try? await notificationManager.requestAuthorization()
                        }
                    }

                    // Sync feed notification schedule
                    Task {
                        await syncFeedNotifications(session: session)
                    }
                }
        }
    }

    /// Sync feed notification schedule on app launch
    /// Fetches schedule from backend and schedules local notifications
    private func syncFeedNotifications(session: SessionManager) async {
        guard let client = session.makeClient() else {
            return // Not authenticated yet
        }

        do {
            let schedule = try await client.getFeedSchedule()
            await FeedNotificationScheduler.shared.scheduleNotifications(for: schedule)
        } catch {
            // Silently fail - notifications will sync when user opens feed settings
            print("[HoustonApp] Failed to sync feed notifications: \(error)")
        }
    }
}

// MARK: - System-Aware Root View
struct SystemAwareRootView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(ThemeManager.self) var themeManager

    var body: some View {
        RootRouterView()
            .onAppear {
                // Update theme when view appears
                themeManager.updateFromEnvironment(colorScheme)
            }
            .onChange(of: colorScheme) { _, newColorScheme in
                // Automatically update theme when system appearance changes
                themeManager.updateFromEnvironment(newColorScheme)
            }
    }
}
