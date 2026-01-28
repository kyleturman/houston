import Foundation
import Combine
import SwiftUI
import Observation

/// Global state manager that listens to SSE events for resource lifecycle changes
/// Broadcasts events when notes, tasks, and goals are created/updated/deleted
/// ViewModels can subscribe to these events to automatically refresh their data
///
/// Performance & Lifecycle:
/// - Automatically disconnects when app enters background (saves battery & data)
/// - Reconnects when app returns to foreground
/// - Uses weak self references to prevent retain cycles
/// - PassthroughSubject doesn't retain events (memory efficient)
///
/// **iOS 26+ Pattern (2025 Best Practices):**
/// Uses `@Observable` for state management while keeping Combine's PassthroughSubject
/// for SSE event broadcasting (events are fire-and-forget, perfect for PassthroughSubject).
///
/// **Concurrency Safety:**
/// - Uses Swift 6.2+ `isolated deinit` to safely access @MainActor properties during cleanup
/// - lifecycleObservers are set up during init and cleaned up in isolated deinit
/// - No `nonisolated(unsafe)` annotations needed with isolated deinit pattern
///
/// Usage in App:
/// ```swift
/// @State private var stateManager = StateManager.shared
///
/// WindowGroup {
///     ContentView()
///         .environment(stateManager)
///         .onAppear {
///             stateManager.connect(session: sessionManager)
///         }
/// }
/// ```
///
/// Usage in Views:
/// ```swift
/// @Environment(StateManager.self) var stateManager
///
/// var body: some View {
///     List(notes) { note in
///         NoteRow(note: note)
///     }
///     .onReceive(stateManager.noteCreatedPublisher) { event in
///         if event.goal_id == goalId {
///             Task { await notesVM.load() }
///         }
///     }
/// }
/// ```
@MainActor
@Observable
class StateManager {
    // MARK: - Singleton
    static let shared = StateManager()

    // MARK: - Event Types

    /// Event data for note_created
    struct NoteCreatedEvent: Decodable {
        let note_id: Int
        let goal_id: Int?
        let title: String?
        let created_at: String?
    }

    /// Event data for note_updated
    struct NoteUpdatedEvent: Decodable {
        let note_id: Int
        let goal_id: Int?
        let title: String?
        let updated_at: String?
    }

    /// Event data for note_deleted
    struct NoteDeletedEvent: Decodable {
        let note_id: Int
        let goal_id: Int?
    }

    /// Event data for task_created
    struct TaskCreatedEvent: Decodable {
        let task_id: Int
        let goal_id: Int?
        let title: String
        let status: String
        let created_at: String
    }

    /// Event data for task_updated
    struct TaskUpdatedEvent: Decodable {
        let task_id: Int
        let goal_id: Int?
        let title: String
        let status: String
        let updated_at: String
    }

    /// Event data for task_completed
    struct TaskCompletedEvent: Decodable {
        let task_id: Int
        let goal_id: Int?
        let title: String
        let status: String
        let updated_at: String
    }

    /// Event data for goal_created
    struct GoalCreatedEvent: Decodable {
        let goal_id: Int
        let title: String
        let status: String
        let created_at: String
    }

    /// Event data for goal_updated
    struct GoalUpdatedEvent: Decodable {
        let goal_id: Int
        let title: String
        let status: String
        let updated_at: String
        /// Next scheduled check-in (included for immediate UI update)
        let next_check_in: NextCheckIn?

        struct NextCheckIn: Decodable {
            let slot: String
            let scheduled_for: String
            let intent: String
        }
    }

    /// Event data for goal_archived
    struct GoalArchivedEvent: Decodable {
        let goal_id: Int
        let title: String
    }

    /// Event data for goal_deleted
    struct GoalDeletedEvent: Decodable {
        let goal_id: Int
        let title: String
    }

    /// Event data for task_deleted
    struct TaskDeletedEvent: Decodable {
        let task_id: Int
        let goal_id: Int?
    }

    /// Event data for task_archived
    struct TaskArchivedEvent: Decodable {
        let task_id: Int
        let goal_id: Int?
        let title: String
    }

    /// Event data for note_archived
    struct NoteArchivedEvent: Decodable {
        let note_id: Int
        let goal_id: Int?
    }

    /// Event data for feed_insights_ready
    struct FeedInsightsReadyEvent: Decodable {
        let insight_count: Int
        let generated_at: String
    }

    /// Event data for agent_history_deleted
    struct AgentHistoryDeletedEvent: Decodable {
        let agent_history_id: Int
        let agentable_type: String
        let agentable_id: Int
    }

    /// Event data for agent_session_reset
    struct AgentSessionResetEvent: Decodable {
        let agentable_type: String
        let agentable_id: Int
        let messages_deleted: Int
        let llm_entries_cleared: Int
    }

    // MARK: - Publishers

    /// Publishes when a note is created
    let noteCreatedPublisher = PassthroughSubject<NoteCreatedEvent, Never>()

    /// Publishes when a note is updated
    let noteUpdatedPublisher = PassthroughSubject<NoteUpdatedEvent, Never>()

    /// Publishes when a note is deleted
    let noteDeletedPublisher = PassthroughSubject<NoteDeletedEvent, Never>()

    /// Publishes when a note is archived
    let noteArchivedPublisher = PassthroughSubject<NoteArchivedEvent, Never>()

    /// Publishes when a task is created
    let taskCreatedPublisher = PassthroughSubject<TaskCreatedEvent, Never>()

    /// Publishes when a task is updated
    let taskUpdatedPublisher = PassthroughSubject<TaskUpdatedEvent, Never>()

    /// Publishes when a task is completed
    let taskCompletedPublisher = PassthroughSubject<TaskCompletedEvent, Never>()

    /// Publishes when a task is deleted
    let taskDeletedPublisher = PassthroughSubject<TaskDeletedEvent, Never>()

    /// Publishes when a task is archived
    let taskArchivedPublisher = PassthroughSubject<TaskArchivedEvent, Never>()

    /// Publishes when a goal is created
    let goalCreatedPublisher = PassthroughSubject<GoalCreatedEvent, Never>()

    /// Publishes when a goal is updated
    let goalUpdatedPublisher = PassthroughSubject<GoalUpdatedEvent, Never>()

    /// Publishes when a goal is archived
    let goalArchivedPublisher = PassthroughSubject<GoalArchivedEvent, Never>()

    /// Publishes when a goal is deleted
    let goalDeletedPublisher = PassthroughSubject<GoalDeletedEvent, Never>()

    /// Publishes when feed insights are ready (notification from UserAgent task)
    let feedInsightsReadyPublisher = PassthroughSubject<FeedInsightsReadyEvent, Never>()

    /// Publishes when an agent history session is deleted
    let agentHistoryDeletedPublisher = PassthroughSubject<AgentHistoryDeletedEvent, Never>()

    /// Publishes when current session is reset/cleared
    let agentSessionResetPublisher = PassthroughSubject<AgentSessionResetEvent, Never>()

    /// Publishes when network is restored and data should be refreshed
    /// ViewModels should listen to this to reload data after reconnection
    let dataRefreshNeededPublisher = PassthroughSubject<Void, Never>()

    // MARK: - State

    var isConnected = false
    var lastError: String?

    /// Tracks if we've ever successfully connected - used to distinguish initial connect from reconnect
    private var hasEverConnected = false

    /// Tracks consecutive SSE connection failures for server unavailable detection
    /// After N consecutive failures, we set serverUnavailable = true
    private var consecutiveSSEFailures = 0

    /// Number of consecutive SSE failures before marking server as unavailable
    /// With backoff [1, 2, 5, 10, 20], 3 failures = ~8 seconds of trying
    private let sseFailureThreshold = 3

    private var sse: SSEClient?
    private var session: SessionManager?
    private var networkMonitor: NetworkMonitor?

    /// Lifecycle observers for app backgrounding/foregrounding
    private var lifecycleObservers: [NSObjectProtocol] = []

    /// Tracks when app entered background (for staleness calculation)
    private var backgroundedAt: Date?

    // MARK: - Initialization

    private init() {
        setupLifecycleObservers()
    }

    // MARK: - Lifecycle Management

    /// Set up app lifecycle observers to handle backgrounding/foregrounding
    /// Disconnects SSE when app enters background to save battery and data
    /// Reconnects when app returns to foreground
    private func setupLifecycleObservers() {
        // Observe app entering background
        let willResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.backgroundedAt = Date()
                print("[StateManager] App entering background, disconnecting SSE")
                self.disconnect()
            }
        }

        // Observe app becoming active (returning from background)
        let didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let session = self.session else { return }

                // Calculate how long app was backgrounded
                let backgroundDuration = self.backgroundedAt.map { Date().timeIntervalSince($0) } ?? 0
                let shouldRefreshData = backgroundDuration > 30
                self.backgroundedAt = nil

                print("[StateManager] App becoming active after \(Int(backgroundDuration))s, checking SSE connection...")

                // Don't try to connect if not authenticated or server unavailable
                guard session.userToken != nil && !session.serverUnavailable else {
                    print("[StateManager] Skipping SSE reconnect - not authenticated or server unavailable")
                    return
                }

                // Wait for app to be fully active
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                // Only reconnect if not already connected
                // This handles initial launch where .onAppear already connected
                guard !self.isConnected else {
                    print("[StateManager] SSE already connected - skipping reconnect")
                    // Trigger data refresh if backgrounded long enough (SSE may have missed events while connected but app inactive)
                    if shouldRefreshData {
                        print("[StateManager] Backgrounded >30s with SSE connected, triggering data refresh")
                        self.dataRefreshNeededPublisher.send()
                    }
                    return
                }

                // SSE disconnected - reconnect
                // Note: SSE onOpen callback will trigger dataRefreshNeededPublisher on reconnection,
                // so we don't need to send it here (would cause double refresh)
                print("[StateManager] SSE disconnected, reconnecting...")
                self.connect(session: session)
            }
        }

        lifecycleObservers = [willResignActiveObserver, didBecomeActiveObserver]
    }

    // MARK: - Public API

    /// Set the network monitor for coordination
    func setNetworkMonitor(_ monitor: NetworkMonitor) {
        self.networkMonitor = monitor
    }

    /// Connect to the global SSE stream
    /// Only connects if user is authenticated (has userToken)
    func connect(session: SessionManager) {
        self.session = session

        // Only connect if user is authenticated
        // SSE endpoint requires authentication - connecting without it causes
        // an endless loop of "connection opened -> server closes -> reconnect"
        guard session.userToken != nil else {
            print("[StateManager] Skipping SSE connection - user not authenticated")
            return
        }

        // Don't connect if server is unavailable
        guard !session.serverUnavailable else {
            print("[StateManager] Skipping SSE connection - server unavailable")
            return
        }

        // Stop any existing connection before creating a new one
        // This prevents duplicate connections if connect() is called multiple times
        if sse != nil {
            print("[StateManager] Stopping existing SSE connection before reconnecting")
            sse?.stop()
            sse = nil
        }

        guard let client = makeClient() else {
            lastError = "Missing server configuration"
            return
        }

        let provider: () throws -> URLRequest = {
            try client.globalStreamURLRequest()
        }

        let sse = SSEClient(
            urlRequestProvider: provider,
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleEvent(event)
                }
            },
            onOpen: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    // Only treat as reconnection if we've connected before AND were disconnected
                    let isReconnection = self.hasEverConnected && !self.isConnected
                    self.isConnected = true
                    self.hasEverConnected = true
                    self.lastError = nil
                    self.consecutiveSSEFailures = 0  // Reset failure counter on successful connect

                    // Clear server unavailable state - we're connected!
                    if self.session?.serverUnavailable == true {
                        print("[StateManager] SSE connected - clearing serverUnavailable")
                        self.session?.serverUnavailable = false
                    }

                    print("[StateManager] Connected to global stream (isReconnection: \(isReconnection))")

                    // If this is a reconnection (not initial connect), notify network monitor and trigger refresh
                    if isReconnection {
                        print("[StateManager] SSE reconnected, notifying NetworkMonitor")
                        self.networkMonitor?.notifyReconnected()

                        // Give network monitor a moment to update UI, then trigger data refresh
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                        print("[StateManager] Broadcasting data refresh event")
                        self.dataRefreshNeededPublisher.send()
                    }
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isConnected = false
                    let nsError = error as NSError

                    // Graceful closures are normal (reconnection) - don't count as failures
                    if let isGraceful = nsError.userInfo["GracefulClosure"] as? Bool, isGraceful {
                        print("[StateManager] Connection closed gracefully, will reconnect")
                        return
                    }

                    // Track consecutive failures for server unavailable detection
                    self.consecutiveSSEFailures += 1
                    self.lastError = error.localizedDescription
                    print("[StateManager] Connection error (\(self.consecutiveSSEFailures)/\(self.sseFailureThreshold)): \(error.localizedDescription)")

                    // After threshold failures, mark server as unavailable
                    // This catches hanging servers that accept TCP but don't respond
                    if self.consecutiveSSEFailures >= self.sseFailureThreshold {
                        if self.session?.serverUnavailable != true {
                            print("[StateManager] SSE failed \(self.consecutiveSSEFailures) times - marking server unavailable")
                            self.session?.serverUnavailable = true
                        }
                    }
                }
            }
        )

        self.sse = sse
        sse.start()
    }

    /// Disconnect from the global SSE stream
    func disconnect() {
        sse?.stop()
        sse = nil
        isConnected = false
        consecutiveSSEFailures = 0  // Reset on intentional disconnect
    }

    /// Clean up lifecycle observers
    /// Uses Swift 6.2+ isolated deinit to safely access @MainActor properties
    isolated deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Private Helpers

    /// Create API client from session
    private func makeClient() -> APIClient? {
        guard let session = session, let baseURL = session.serverURL else { return nil }
        return APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { session.deviceToken },
            userTokenProvider: { session.userToken }
        )
    }

    /// Handle incoming SSE events
    ///
    /// IMPORTANT: When adding new global lifecycle event types:
    /// 1. Add event type to SSEClient.EventType enum first
    /// 2. Add event struct above (lines 48-119)
    /// 3. Add publisher property (lines 121-148)
    /// 4. Add case in switch below to decode and publish
    ///
    /// See ios/CLAUDE.md "Adding New SSE Event Types" section for full instructions.
    private func handleEvent(_ event: SSEClient.Event) {
        guard let data = event.data.data(using: .utf8) else { return }

        switch event.type {
        case .welcome:
            print("[StateManager] Received welcome event")

        case .keepalive:
            // Heartbeat - no action needed
            break

        // Note events
        case .note_created:
            do {
                let parsed = try JSONDecoder().decode(NoteCreatedEvent.self, from: data)
                noteCreatedPublisher.send(parsed)
                print("[StateManager] Note created: \(parsed.note_id)")
            } catch {
                print("[StateManager] Failed to decode note_created event: \(error)")
            }

        case .note_updated:
            do {
                let parsed = try JSONDecoder().decode(NoteUpdatedEvent.self, from: data)
                noteUpdatedPublisher.send(parsed)
                print("[StateManager] Note updated: \(parsed.note_id)")
            } catch {
                print("[StateManager] Failed to decode note_updated event: \(error)")
            }

        case .note_deleted:
            do {
                let parsed = try JSONDecoder().decode(NoteDeletedEvent.self, from: data)
                noteDeletedPublisher.send(parsed)
                print("[StateManager] Note deleted: \(parsed.note_id)")
            } catch {
                print("[StateManager] Failed to decode note_deleted event: \(error)")
            }

        // Task events
        case .task_created:
            do {
                let parsed = try JSONDecoder().decode(TaskCreatedEvent.self, from: data)
                taskCreatedPublisher.send(parsed)
                print("[StateManager] Task created: \(parsed.task_id)")
            } catch {
                print("[StateManager] Failed to decode task_created event: \(error)")
            }

        case .task_updated:
            do {
                let parsed = try JSONDecoder().decode(TaskUpdatedEvent.self, from: data)
                taskUpdatedPublisher.send(parsed)
                print("[StateManager] Task updated: \(parsed.task_id)")
            } catch {
                print("[StateManager] Failed to decode task_updated event: \(error)")
            }

        case .task_completed:
            do {
                let parsed = try JSONDecoder().decode(TaskCompletedEvent.self, from: data)
                taskCompletedPublisher.send(parsed)
                print("[StateManager] Task completed: \(parsed.task_id)")
            } catch {
                print("[StateManager] Failed to decode task_completed event: \(error)")
            }

        // Goal events
        case .goal_created:
            do {
                let parsed = try JSONDecoder().decode(GoalCreatedEvent.self, from: data)
                goalCreatedPublisher.send(parsed)
                print("[StateManager] Goal created: \(parsed.goal_id)")
            } catch {
                print("[StateManager] Failed to decode goal_created event: \(error)")
            }

        case .goal_updated:
            do {
                let parsed = try JSONDecoder().decode(GoalUpdatedEvent.self, from: data)
                goalUpdatedPublisher.send(parsed)
                print("[StateManager] Goal updated: \(parsed.goal_id)")
            } catch {
                print("[StateManager] Failed to decode goal_updated event: \(error)")
            }

        case .goal_archived:
            do {
                let parsed = try JSONDecoder().decode(GoalArchivedEvent.self, from: data)
                goalArchivedPublisher.send(parsed)
                print("[StateManager] Goal archived: \(parsed.goal_id)")
            } catch {
                print("[StateManager] Failed to decode goal_archived event: \(error)")
            }

        case .goal_deleted:
            do {
                let parsed = try JSONDecoder().decode(GoalDeletedEvent.self, from: data)
                goalDeletedPublisher.send(parsed)
                print("[StateManager] Goal deleted: \(parsed.goal_id)")
            } catch {
                print("[StateManager] Failed to decode goal_deleted event: \(error)")
            }

        case .note_archived:
            do {
                let parsed = try JSONDecoder().decode(NoteArchivedEvent.self, from: data)
                noteArchivedPublisher.send(parsed)
                print("[StateManager] Note archived: \(parsed.note_id)")
            } catch {
                print("[StateManager] Failed to decode note_archived event: \(error)")
            }

        case .task_deleted:
            do {
                let parsed = try JSONDecoder().decode(TaskDeletedEvent.self, from: data)
                taskDeletedPublisher.send(parsed)
                print("[StateManager] Task deleted: \(parsed.task_id)")
            } catch {
                print("[StateManager] Failed to decode task_deleted event: \(error)")
            }

        case .task_archived:
            do {
                let parsed = try JSONDecoder().decode(TaskArchivedEvent.self, from: data)
                taskArchivedPublisher.send(parsed)
                print("[StateManager] Task archived: \(parsed.task_id)")
            } catch {
                print("[StateManager] Failed to decode task_archived event: \(error)")
            }

        // Feed insights ready
        case .feed_insights_ready:
            do {
                let parsed = try JSONDecoder().decode(FeedInsightsReadyEvent.self, from: data)
                feedInsightsReadyPublisher.send(parsed)
                print("[StateManager] Feed insights ready: \(parsed.insight_count) insights")
            } catch {
                print("[StateManager] Failed to decode feed_insights_ready event: \(error)")
            }

        // Agent history events
        case .agent_history_deleted:
            do {
                let parsed = try JSONDecoder().decode(AgentHistoryDeletedEvent.self, from: data)
                agentHistoryDeletedPublisher.send(parsed)
                print("[StateManager] Agent history deleted: \(parsed.agent_history_id)")
            } catch {
                print("[StateManager] Failed to decode agent_history_deleted event: \(error)")
            }

        case .agent_session_reset:
            do {
                let parsed = try JSONDecoder().decode(AgentSessionResetEvent.self, from: data)
                agentSessionResetPublisher.send(parsed)
                print("[StateManager] Agent session reset: \(parsed.agentable_type)#\(parsed.agentable_id)")
            } catch {
                print("[StateManager] Failed to decode agent_session_reset event: \(error)")
            }

        default:
            break
        }
    }
}
