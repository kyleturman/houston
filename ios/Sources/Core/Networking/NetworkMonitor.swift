import Foundation
import Network
import SwiftUI
import Observation

/// Monitors network connectivity status using NWPathMonitor
/// Manages connectivity banner state and coordinates with StateManager for data refresh
///
/// **iOS 18+ Best Practices:**
/// - Uses NWPathMonitor (Apple's recommended approach)
/// - Debounces rapid network changes to prevent UI flicker
/// - Runs on background queue (no main thread blocking)
///
/// Usage:
/// ```swift
/// @Environment(NetworkMonitor.self) var networkMonitor
///
/// var body: some View {
///     VStack(spacing: 0) {
///         if networkMonitor.showBanner {
///             ConnectivityBanner(status: networkMonitor.status)
///         }
///         MainContent()
///     }
/// }
/// ```
@MainActor
@Observable
final class NetworkMonitor: @unchecked Sendable {
    enum Status: Equatable {
        case online
        case offline
        case reconnecting
    }

    // MARK: - Public State

    /// Current connectivity status
    private(set) var status: Status = .online

    /// Whether to show the connectivity banner
    private(set) var showBanner: Bool = false

    /// Whether the device is currently connected to the internet
    var isConnected: Bool { status == .online }

    // MARK: - Private State

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.heyhouston.networkmonitor")

    /// Debounce task to prevent rapid status changes from causing UI flicker
    private var debounceTask: Task<Void, Never>?

    /// Task for auto-dismissing "back online" banner
    private var dismissTask: Task<Void, Never>?

    /// Previous status to detect changes
    private var previousStatus: Status = .online

    // MARK: - Configuration

    /// How long to wait before updating status (prevents flicker on unstable networks)
    private let debounceDelay: TimeInterval = 2.0

    /// How long to show "Back online" banner before auto-dismissing
    private let backOnlineDuration: TimeInterval = 2.0

    // MARK: - Initialization

    init() {
        self.monitor = NWPathMonitor()

        // Start monitoring on background queue
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }

        monitor.start(queue: queue)
    }

    /// Clean up resources
    /// Uses isolated deinit to safely access @MainActor properties during cleanup
    /// Note: Since NetworkMonitor is typically a singleton, this rarely executes,
    /// but it's still good practice for proper resource management
    isolated deinit {
        debounceTask?.cancel()
        dismissTask?.cancel()
        monitor.cancel()
    }

    // MARK: - Public API

    /// Notify the monitor that SSE has successfully reconnected
    /// This triggers the transition from "reconnecting" to "online"
    func notifyReconnected() {
        guard status == .reconnecting else { return }

        print("[NetworkMonitor] SSE reconnected, transitioning to online")
        updateStatus(.online, showBanner: true, autoDismiss: true)
    }

    /// Manually trigger refresh (for testing)
    func refresh() {
        // Force a status check with current path
        handlePathUpdate(monitor.currentPath)
    }

    // MARK: - Private Methods

    /// Handle network path updates from NWPathMonitor
    private func handlePathUpdate(_ path: NWPath) {
        let isConnected = path.status == .satisfied
        let newStatus: Status = isConnected ? .online : .offline

        // Cancel any pending debounce
        debounceTask?.cancel()

        // If going offline, update immediately (users should know right away)
        if newStatus == .offline && status != .offline {
            print("[NetworkMonitor] Network lost, updating immediately")
            updateStatus(.offline, showBanner: true, autoDismiss: false)
            return
        }

        // If coming back online, debounce to ensure stability
        if newStatus == .online && status != .online {
            print("[NetworkMonitor] Network detected, debouncing for \(debounceDelay)s...")

            // Show "reconnecting" immediately
            if status == .offline {
                updateStatus(.reconnecting, showBanner: true, autoDismiss: false)
            }

            // Debounce the final "online" status
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

                guard !Task.isCancelled else { return }

                print("[NetworkMonitor] Debounce complete, network is stable")
                // Don't transition to online yet - wait for SSE to confirm reconnection
                // StateManager will call notifyReconnected() when SSE connects
            }
        }
    }

    /// Update status and banner visibility
    private func updateStatus(_ newStatus: Status, showBanner: Bool, autoDismiss: Bool) {
        previousStatus = status
        status = newStatus
        self.showBanner = showBanner

        print("[NetworkMonitor] Status: \(previousStatus) -> \(newStatus), banner: \(showBanner)")

        // Auto-dismiss banner for "back online" after delay
        if autoDismiss && newStatus == .online {
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(backOnlineDuration * 1_000_000_000))

                guard !Task.isCancelled else { return }

                print("[NetworkMonitor] Auto-dismissing 'back online' banner")
                self.showBanner = false
            }
        } else {
            dismissTask?.cancel()
        }
    }
}
