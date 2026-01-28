import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ChatViewModel {

    // MARK: - Observable Properties

    /// Chat messages displayed in the UI
    var messages: [ChatMessage] = []

    /// Current text input from the user
    var input: String = ""

    /// Whether the agent is actively processing (thinking or executing tools)
    var isStreaming: Bool = false

    /// Whether a message is actively streaming (suppresses "Thinking..." indicator)
    var isMessageStreaming: Bool = false

    /// Error message to display to the user
    var errorMessage: String?

    /// Task information (for retry banner when task is paused)
    var currentTask: AgentTaskModel?

    /// Goal information (for tool cells to access accent color)
    var currentGoal: Goal?

    // MARK: - Computed Properties

    /// Current agent activity status for display in the activity bar
    var activityStatus: String {
        // Find the most recent tool that's in progress
        // Only user-facing tools create ThreadMessages (backend enforces this)
        if let activeTool = messages.last(where: { message in
            guard let tool = message.tool else { return false }
            return tool.status == .inProgress
        })?.tool {
            return activeTool.displayTitle
        }

        // If streaming but no active tools, show thinking
        if isStreaming && !isMessageStreaming {
            return "Thinking..."
        }

        // Default: connected and ready
        return "Connected"
    }

    // MARK: - Private Properties

    /// Data source for loading and sending messages
    private let dataSource: ChatDataSource

    /// Agent chat context (if using AgentChatDataSource)
    var agentContext: AgentChatDataSource.Context? {
        (dataSource as? AgentChatDataSource)?.context
    }

    /// Session manager for authentication and server URL
    private var session: SessionManager

    /// Server-sent events client for real-time updates
    private var sse: SSEClient?

    /// ID of the currently streaming message
    private var currentStreamingId: String?

    /// Last message text sent (for retry functionality)
    private var lastSentText: String?

    /// Timer for polling message updates during streaming
    private var pollingTimer: Timer?

    /// Error debouncing to prevent alert spam
    private var lastErrorTime: Date?
    private let errorDebounceInterval: TimeInterval = 3.0

    /// Flag to prevent concurrent history loads
    private var isLoadingHistory = false

    /// Flag to prevent concurrent message refreshes
    private var isRefreshingMessages = false

    /// Flag to track if initial setup is complete
    private var isInitialized = false

    // MARK: - Pagination Properties

    /// Total number of sessions available (current + archived)
    var totalSessions: Int = 1 // Default to 1 (current session)

    /// Number of sessions currently loaded
    var loadedSessions: Int = 1 // Default to 1 (current session)

    /// Whether there are more sessions to load
    var hasMoreSessions: Bool {
        loadedSessions < totalSessions
    }

    /// Whether we're currently loading more sessions
    var isLoadingMoreSessions: Bool = false

    /// Initial session count to load (current + 2 previous sessions)
    private let initialSessionCount = 3

    // MARK: - Initialization

    /// Initialize with a data source
    init(session: SessionManager, dataSource: ChatDataSource, goal: Goal? = nil) {
        self.session = session
        self.dataSource = dataSource
        self.currentGoal = goal

        // Initialize the tool registry for displaying tool activities
        ToolFactory.initializeRegistry()
    }

    /// Convenience initializer for agent chats (backward compatibility)
    convenience init(session: SessionManager, context: AgentChatDataSource.Context, goal: Goal? = nil) {
        guard let baseURL = session.serverURL else {
            fatalError("Session must have a server URL")
        }

        let client = APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { session.deviceToken },
            userTokenProvider: { session.userToken }
        )

        let dataSource = AgentChatDataSource(context: context, client: client)
        self.init(session: session, dataSource: dataSource, goal: goal)
    }

    /// Cleanup resources when view model is deallocated
    /// Uses Swift 6.2+ isolated deinit to safely access @MainActor properties
    isolated deinit {
        pollingTimer?.invalidate()
        sse?.stop()
    }

    // MARK: - Public API

    /// Initialize the view model (call once from ChatView.task)
    /// IMPORTANT: Does NOT block - loads data in background
    /// **Swift 6.2 Pattern**: Uses nonisolated async for background work
    func initialize() async {
        guard !isInitialized else {
            print("[ChatViewModel] initialize() skipped - already initialized")
            return
        }
        isInitialized = true
        print("[ChatViewModel] initialize() starting - non-blocking")

        // Start SSE stream immediately (doesn't block)
        print("[ChatViewModel] About to call startStream()")
        startStream()
        print("[ChatViewModel] startStream() returned")

        // Load history in background - nonisolated method runs off MainActor
        print("[ChatViewModel] About to spawn task for loadHistory()")
        Task {
            print("[ChatViewModel] Task started, calling loadHistory()")
            await self.loadHistory()
        }
        print("[ChatViewModel] initialize() returning")
    }

    /// Initialize without starting SSE stream (for preloading).
    ///
    /// Use this when preloading a ChatViewModel in the background.
    /// Call `startStream()` separately when the chat sheet opens.
    func initializeWithoutStream() async {
        guard !isInitialized else {
            print("[ChatViewModel] initializeWithoutStream() skipped - already initialized")
            return
        }
        isInitialized = true
        print("[ChatViewModel] initializeWithoutStream() - loading messages only")

        // Only load history, don't start SSE
        await loadHistory()
    }

    /// Load chat history and start listening for updates
    func loadHistory() async {
        // Prevent concurrent loads
        guard !isLoadingHistory else {
            print("[ChatViewModel] loadHistory() skipped - already loading")
            return
        }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        print("[ChatViewModel] loadHistory() started")
        errorMessage = nil
        do {
            let loadedMessages: [ChatMessage]
            let meta: SessionPaginationMeta?

            // Use pagination for agent chats (goals and user agent)
            if let agentDataSource = dataSource as? AgentChatDataSource {
                switch agentDataSource.context {
                case .goal, .userAgent:
                    // Load initial sessions (current + 2 previous)
                    (loadedMessages, meta) = try await agentDataSource.loadMessages(sessionCount: initialSessionCount)
                    print("[ChatViewModel] loadHistory() received \(loadedMessages.count) messages with pagination")

                    // Update pagination state
                    if let meta = meta {
                        self.totalSessions = meta.total_sessions
                        self.loadedSessions = meta.loaded_sessions
                        print("[ChatViewModel] Pagination: loaded \(meta.loaded_sessions) of \(meta.total_sessions) sessions, has_more=\(meta.has_more)")
                    }
                case .task:
                    // Tasks don't use pagination yet
                    loadedMessages = try await dataSource.loadMessages()
                    print("[ChatViewModel] loadHistory() received \(loadedMessages.count) messages (no pagination)")
                }
            } else {
                // Non-agent data sources don't use pagination
                loadedMessages = try await dataSource.loadMessages()
                print("[ChatViewModel] loadHistory() received \(loadedMessages.count) messages (no pagination)")
            }

            // Deduplicate tool messages on initial load
            messages = Self.deduplicateToolMessages(loadedMessages)
        } catch is CancellationError {
            // Task was cancelled (e.g., user swiped to different goal) - this is expected, don't show error
            print("[ChatViewModel] loadHistory() cancelled")
        } catch {
            print("[ChatViewModel] loadHistory() failed: \(error)")
            setError("Failed to load messages")
        }

        // Load task info if we're in a task context (for retry banner)
        if let agentDataSource = dataSource as? AgentChatDataSource,
           case .task(let taskId) = agentDataSource.context {
            await loadTaskInfo(taskId: taskId)
        }
    }

    /// Send the current input message
    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        input = ""
        lastSentText = text

        // Optimistically add user message to UI
        let temp = ChatMessage(
            id: UUID().uuidString,
            content: text,
            source: .user,
            createdAt: Date()
        )
        messages.append(temp)

        // Show typing indicator immediately while waiting for backend
        isStreaming = true

        // Send to backend via data source
        do {
            try await dataSource.sendMessage(text: text)
            // SSE events during sendMessage may have turned off isStreaming prematurely
            // Keep showing typing indicator if agent hasn't responded yet
            if messages.last?.source == .user {
                isStreaming = true
            }
        } catch {
            isStreaming = false
            setError("Failed to send message")
        }
    }

    /// Load more sessions (for infinite scroll)
    func loadMoreSessions() async {
        // Only load more if we have more sessions to load
        guard hasMoreSessions,
              !isLoadingMoreSessions,
              let agentDataSource = dataSource as? AgentChatDataSource else {
            return
        }

        // Only support pagination for goals and user agent
        switch agentDataSource.context {
        case .goal, .userAgent:
            break // Continue with loading
        case .task:
            return // Tasks don't support pagination
        }

        isLoadingMoreSessions = true
        defer { isLoadingMoreSessions = false }

        print("[ChatViewModel] loadMoreSessions() loading session \(loadedSessions + 1) of \(totalSessions)")

        do {
            // Load one more session
            let newSessionCount = loadedSessions + 1
            let (loadedMessages, meta) = try await agentDataSource.loadMessages(sessionCount: newSessionCount)

            print("[ChatViewModel] loadMoreSessions() received \(loadedMessages.count) total messages")

            // Update pagination state
            if let meta = meta {
                self.totalSessions = meta.total_sessions
                self.loadedSessions = meta.loaded_sessions
                print("[ChatViewModel] Pagination: now loaded \(meta.loaded_sessions) of \(meta.total_sessions) sessions")
            }

            // Deduplicate and update messages
            messages = Self.deduplicateToolMessages(loadedMessages)
        } catch is CancellationError {
            // Task was cancelled - this is expected, don't show error
            print("[ChatViewModel] loadMoreSessions() cancelled")
        } catch {
            print("[ChatViewModel] loadMoreSessions() failed: \(error)")
            setError("Failed to load more messages")
        }
    }

    /// Retry sending the last message (used after errors)
    func retryLast() async {
        guard let text = lastSentText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }

        do {
            try await dataSource.sendMessage(text: text)
        } catch {
            setError("Failed to retry. Please try again.")
        }
    }

    /// Retry a paused task
    func retryTask() async {
        guard let agentDataSource = dataSource as? AgentChatDataSource,
              case .task(let taskId) = agentDataSource.context,
              let task = currentTask,
              task.status == .paused,
              let client = makeClient() else { return }

        do {
            let resource = try await client.retryTask(taskId: taskId)
            self.currentTask = AgentTaskModel.from(resource: resource)
        } catch {
            setError("Failed to retry task: \(error.localizedDescription)")
        }
    }

    /// Retry an error message - re-processes the user message that triggered the error
    /// - Parameter messageId: The error message ID to retry
    func retryErrorMessage(messageId: String) async {
        guard let client = makeClient() else { return }

        do {
            _ = try await client.retryErrorMessage(messageId: messageId)
            // Remove the error message from local state with animation
            withAnimation(.easeOut(duration: 0.25)) {
                messages.removeAll { $0.id == messageId }
            }
            // Set streaming state since orchestrator will start
            isStreaming = true
        } catch {
            setError("Failed to retry: \(error.localizedDescription)")
        }
    }

    /// Dismiss (delete) an error message
    /// - Parameter messageId: The error message ID to dismiss
    func dismissErrorMessage(messageId: String) async {
        guard let client = makeClient() else { return }

        do {
            try await client.dismissErrorMessage(messageId: messageId)
            // Remove the error message from local state with animation
            withAnimation(.easeOut(duration: 0.25)) {
                messages.removeAll { $0.id == messageId }
            }
        } catch {
            setError("Failed to dismiss: \(error.localizedDescription)")
        }
    }

    /// Start listening for real-time updates via SSE
    func startStream() {
        // Prevent duplicate streams
        if sse != nil {
            print("[ChatViewModel] startStream() skipped - stream already active")
            return
        }

        print("[ChatViewModel] startStream() starting")

        // Check if auto-start is enabled
        guard dataSource.autoStartStream else { return }

        // Don't start stream for completed tasks
        if let agentDataSource = dataSource as? AgentChatDataSource,
           case .task(_) = agentDataSource.context,
           currentTask?.status == .completed {
            return
        }

        let provider: () throws -> URLRequest = {
            return try self.dataSource.streamRequest()
        }

        let sse = SSEClient(
            urlRequestProvider: provider,
            onEvent: { [weak self] evt in self?.handle(event: evt) },
            onOpen: { [weak self] in
                DispatchQueue.main.async {
                    self?.errorMessage = nil
                    self?.startPolling()
                }
            },
            onError: { [weak self] err in
                DispatchQueue.main.async {
                    let nsError = err as NSError

                    // Graceful closures are normal (reconnection) - don't show error
                    if let isGraceful = nsError.userInfo["GracefulClosure"] as? Bool, isGraceful {
                        return
                    }

                    // Check for cancellation (intentional stop) - don't show error
                    if nsError.code == NSURLErrorCancelled && nsError.domain == NSURLErrorDomain {
                        return
                    }

                    // Check for 422 (completed task) - don't show error
                    if let statusCode = nsError.userInfo["HTTPStatusCode"] as? Int, statusCode == 422 {
                        return
                    }

                    // Only show error for actual connection problems
                    print("[ChatViewModel] SSE error (will retry): \(err.localizedDescription)")
                    // Removed annoying error message - SSE auto-reconnects silently
                    // self?.setError("Connection issue. Retrying...")
                    self?.stopPolling()
                }
            }
        )

        self.sse = sse
        sse.start()
    }

    /// Stop listening for real-time updates
    func stopStream() {
        sse?.stop()
        sse = nil
        Task { @MainActor in stopPolling() }
    }

    // MARK: - Computed Properties

    /// Whether to show the retry banner (for paused tasks)
    var shouldShowRetryBanner: Bool {
        currentTask?.status == .paused
    }

    /// Whether to show tool activities in messages
    var showsToolActivities: Bool {
        dataSource.showsToolActivities
    }

    /// Check if current context is a specific task
    func isTaskContext(_ taskId: String) -> Bool {
        guard let agentDataSource = dataSource as? AgentChatDataSource else { return false }
        if case .task(let id) = agentDataSource.context { return id == taskId }
        return false
    }

    // MARK: - Internal State Management

    /// Update session reference (called when session changes)
    func setSession(_ session: SessionManager) {
        self.session = session
    }

    // MARK: - Private Helpers

    /// Create an authenticated API client
    private func makeClient() -> APIClient? {
        guard let base = session.serverURL else { return nil }
        return APIClient(
            baseURL: base,
            deviceTokenProvider: { self.session.deviceToken },
            userTokenProvider: { self.session.userToken }
        )
    }

    /// Set an error message with debouncing to prevent spam
    private func setError(_ message: String) {
        let now = Date()
        if let lastTime = lastErrorTime, now.timeIntervalSince(lastTime) < errorDebounceInterval {
            return // Too soon after last error
        }
        lastErrorTime = now
        errorMessage = message
    }

    /// Refresh messages from the data source
    func refreshMessages() async {
        // Skip refresh for linear data sources (goal creation, etc.)
        // Linear chats don't persist to backend, so there's nothing to refresh
        // Calling loadMessages() would return empty and wipe existing messages
        if dataSource is LinearChatDataSource {
            print("[ChatViewModel] refreshMessages() skipped - linear data source has no server-side history")
            return
        }

        // Prevent concurrent refreshes
        guard !isRefreshingMessages else {
            print("[ChatViewModel] refreshMessages() skipped - already refreshing")
            return
        }
        isRefreshingMessages = true
        defer { isRefreshingMessages = false }

        print("[ChatViewModel] refreshMessages() called")
        do {
            let loadedMessages: [ChatMessage]
            let meta: SessionPaginationMeta?

            // Use pagination if we're in agent chat mode with loaded sessions > 0
            if let agentDataSource = dataSource as? AgentChatDataSource,
               loadedSessions > 0 {
                switch agentDataSource.context {
                case .goal, .userAgent:
                    // Use at least initialSessionCount to handle session archival edge case:
                    // When archival happens, the user's message moves to an archived session.
                    // If loadedSessions=1, we'd miss it. Using max() ensures we always load
                    // enough sessions to include recently archived content.
                    let sessionCount = max(loadedSessions, initialSessionCount)
                    (loadedMessages, meta) = try await agentDataSource.loadMessages(sessionCount: sessionCount)

                    // Update pagination state
                    if let meta = meta {
                        self.totalSessions = meta.total_sessions
                        self.loadedSessions = meta.loaded_sessions
                    }
                case .task:
                    loadedMessages = try await dataSource.loadMessages()
                    meta = nil
                }
            } else {
                loadedMessages = try await dataSource.loadMessages()
                meta = nil
            }

            // Deduplicate tool messages with the same activity_id
            // Keep only the latest message for each tool activity
            let deduplicatedMessages = Self.deduplicateToolMessages(loadedMessages)

            // Preserve any streaming messages during polling
            let streamingMessages = messages.filter { $0.isStreaming }

            // Merge loaded messages with streaming messages
            var combinedMessages = deduplicatedMessages
            for streamingMsg in streamingMessages {
                if !deduplicatedMessages.contains(where: { $0.id == streamingMsg.id }) {
                    combinedMessages.append(streamingMsg)
                }
            }

            self.messages = combinedMessages
        } catch is CancellationError {
            // Task was cancelled - this is expected, don't show error
            print("[ChatViewModel] refreshMessages() cancelled")
        } catch {
            self.setError("Failed to load messages")
        }
    }

    /// Deduplicate tool messages with the same activity ID
    /// Keeps only the latest message for each tool activity
    private static func deduplicateToolMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        var seen: [String: ChatMessage] = [:] // tool_activity.id -> latest message
        var result: [ChatMessage] = []

        for message in messages {
            // If message has tool activity, track by activity ID
            if let tool = message.tool {
                if let existing = seen[tool.id] {
                    // Keep the message with higher ID (created later)
                    // If IDs are equal, keep the newer one (later in array = fresher from API)
                    if message.id >= existing.id {
                        seen[tool.id] = message
                    }
                } else {
                    seen[tool.id] = message
                }
            } else {
                // Non-tool messages always included
                result.append(message)
            }
        }

        // Add deduplicated tool messages
        result.append(contentsOf: seen.values.sorted { $0.id < $1.id })

        // Sort by ID to maintain chronological order
        return result.sorted { $0.id < $1.id }
    }

    /// Load task information (for retry banner)
    private func loadTaskInfo(taskId: String) async {
        guard let client = makeClient() else { return }

        do {
            let resource = try await client.getTask(id: taskId)
            self.currentTask = AgentTaskModel.from(resource: resource)
        } catch {
            // Silently fail - task info is optional
        }
    }

    /// Start polling for message updates every 2 seconds
    ///
    /// **Why polling is necessary:**
    /// SSE events notify us when tool activities occur (tool_start, tool_progress, tool_completion),
    /// but the actual ThreadMessage content with tool_activity metadata is stored server-side.
    /// Polling fetches the updated ThreadMessages to display the full tool activity details.
    ///
    /// **Architecture Decision:**
    /// This hybrid approach (SSE for events + polling for content) balances real-time updates
    /// with bandwidth efficiency. An alternative would be to send full message content in SSE
    /// events, but that would significantly increase SSE payload size.
    ///
    /// **2025 Optimization:** Skip polling during active message streaming to prevent race conditions
    /// where polling fetches the persisted ThreadMessage before streaming completes
    private func startPolling() {
        pollingTimer?.invalidate() // Prevent duplicate timers
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Only poll if agent is streaming BUT NOT actively streaming a message
                // This prevents fetching the ThreadMessage before streaming completes (race condition)
                if self.isStreaming && !self.isMessageStreaming {
                    await self.refreshMessages()
                }
            }
        }
    }

    /// Stop polling for updates
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - SSE Event Handling

    /// Handle server-sent events for real-time updates
    private func handle(event: SSEClient.Event) {
        print("[ChatViewModel] SSE event received: type=\(event.type)")

        // Let data source handle custom events first
        if dataSource.handleCustomEvent(event) {
            return
        }

        guard let data = event.data.data(using: .utf8) else { return }

        switch event.type {
        case .welcome:
            break

        case .error:
            // Backend error - stop streaming and refresh to show error message
            DispatchQueue.main.async {
                self.isStreaming = false
                self.isMessageStreaming = false
                if let sid = self.currentStreamingId,
                   let idx = self.messages.lastIndex(where: { $0.isStreaming && $0.id == sid }) {
                    self.messages.remove(at: idx)
                }
                self.currentStreamingId = nil
                Task { await self.refreshMessages() }
            }

        case .processing:
            // Immediate feedback - message received, job queued (before Sidekiq picks it up)
            DispatchQueue.main.async {
                self.isStreaming = true
                self.isMessageStreaming = false // Show "Thinking..."
            }

        case .turn_start:
            // Agent started processing (Sidekiq job running)
            DispatchQueue.main.async {
                self.isStreaming = true
                self.isMessageStreaming = false // Show "Thinking..."
            }

        case .think:
            // Internal reasoning - don't show to user
            break

        case .start:
            // Message streaming started
            DispatchQueue.main.async {
                self.isStreaming = true
                self.isMessageStreaming = true // Hide "Thinking..."
                let sid = UUID().uuidString
                self.currentStreamingId = sid
                let msg = ChatMessage(
                    id: sid,
                    content: "",
                    source: .agent,
                    createdAt: Date(),
                    isStreaming: true
                )
                // Animate the transition from typing indicator to streaming message
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.messages.append(msg)
                }
            }

        case .chunk:
            // Display chunks immediately - backend paces them at ~60ms intervals
            struct Chunk: Decodable { let delta: String }
            if let chunk = try? JSONDecoder().decode(Chunk.self, from: data) {
                DispatchQueue.main.async {
                    if let sid = self.currentStreamingId,
                       let idx = self.messages.lastIndex(where: { $0.isStreaming && $0.id == sid }) {
                        self.messages[idx].content += chunk.delta
                    } else {
                        // Create streaming message if it doesn't exist
                        let sid = UUID().uuidString
                        self.currentStreamingId = sid
                        let msg = ChatMessage(
                            id: sid,
                            content: chunk.delta,
                            source: .agent,
                            createdAt: Date(),
                            isStreaming: true
                        )
                        self.messages.append(msg)
                    }
                }
            }

        case .done:
            // Message streaming complete
            DispatchQueue.main.async {
                self.isStreaming = false
                self.isMessageStreaming = false

                if let sid = self.currentStreamingId,
                   let idx = self.messages.lastIndex(where: { $0.isStreaming && $0.id == sid }) {
                    self.messages[idx].isStreaming = false
                }

                // Keep currentStreamingId temporarily for .message event deduplication
                // It will be cleared in .message or .turn_done
            }

        case .message:
            // ThreadMessage created/updated
            // Parse to check message source - only turn off streaming for agent messages
            struct MessageEvent: Decodable { let source: String? }
            let messageSource = (try? JSONDecoder().decode(MessageEvent.self, from: data))?.source

            DispatchQueue.main.async {
                // If we have a streaming message, remove it - the DB version will appear via polling
                if let sid = self.currentStreamingId,
                   let idx = self.messages.lastIndex(where: { $0.id == sid }) {
                    self.messages.remove(at: idx)
                }

                // Clear streaming ID but keep isStreaming true until refresh completes
                // This prevents the typing indicator from flashing off before the message appears
                self.currentStreamingId = nil
                self.isMessageStreaming = false

                // Refresh to get the persisted message
                // Only turn off streaming if this is an agent or error message
                // User messages shouldn't turn off streaming - agent is still processing
                Task {
                    await self.refreshMessages()
                    if messageSource == "agent" || messageSource == "error" {
                        self.isStreaming = false
                    }
                }
            }

        case .task_update:
            // Task status changed - update inline task cells
            struct TaskUpdate: Decodable { let task_id: Int; let status: String; let title: String? }
            if let taskUpdate = try? JSONDecoder().decode(TaskUpdate.self, from: data) {
                DispatchQueue.main.async {
                    self.updateTaskStatus(taskId: String(taskUpdate.task_id), status: taskUpdate.status)
                }
            }

        case .tool_execution_start:
            // Tool execution started - backend handles display_message in ThreadMessage metadata
            // No need to manually update task activity here
            break

        case .turn_done:
            // Agent finished processing turn
            DispatchQueue.main.async {
                self.isStreaming = false
                self.isMessageStreaming = false
                if let sid = self.currentStreamingId,
                   let idx = self.messages.lastIndex(where: { $0.isStreaming && $0.id == sid }) {
                    if self.messages[idx].content.isEmpty {
                        self.messages.remove(at: idx)
                    } else {
                        self.messages[idx].isStreaming = false
                    }
                    self.currentStreamingId = nil
                }
            }

        case .task_completed:
            // Task completed - update status and stop streaming
            struct TaskCompleted: Decodable { let message: String?; let task_id: Int?; let status: String? }
            if let tc = try? JSONDecoder().decode(TaskCompleted.self, from: data) {
                DispatchQueue.main.async {
                    self.isStreaming = false
                    if let agentContext = self.agentContext,
                       case .task(let taskId) = agentContext,
                       let tcTaskId = tc.task_id,
                       String(tcTaskId) == taskId {
                        self.currentTask?.status = .completed
                    }
                    self.stopStream()
                }
            }

        case .goal_archived:
            // Goal archived - stop streaming
            DispatchQueue.main.async {
                self.isStreaming = false
                self.stopStream()
            }

        case .keepalive:
            // Heartbeat from backend - ignore
            break

        default:
            break
        }
    }

    /// Update task status in existing create_task tool activities
    private func updateTaskStatus(taskId: String, status: String) {
        var didChange = false
        for i in 0..<messages.count {
            if var tool = messages[i].tool,
               tool.toolName == "create_task" {
                let updateMetadata: [String: Any] = ["task_status": status, "task_id": taskId]
                tool.update(from: updateMetadata)
                messages[i].tool = tool
                didChange = true
            }
        }
        if didChange {
            self.messages = self.messages // Trigger update
        }
    }

}
