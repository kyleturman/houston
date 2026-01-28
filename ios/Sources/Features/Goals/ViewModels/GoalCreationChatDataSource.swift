import Foundation
import SwiftUI
import Observation

/// Data source for goal creation wizard chat
/// Extends LinearChatDataSource with goal-specific logic
@MainActor
@Observable
class GoalCreationChatDataSource: LinearChatDataSource, @unchecked Sendable {

    // MARK: - Cached State (survives sheet dismissal)

    /// Cached conversation state for recovery after accidental dismiss
    private struct CachedState {
        let conversationHistory: [(role: String, content: String)]
        let messages: [ChatMessage]
    }

    /// Static cache that persists across sheet presentations (session-only, not persisted to disk)
    private static var cachedState: CachedState?

    /// Whether there's cached state to restore
    static var hasCachedState: Bool {
        cachedState != nil
    }

    /// Clear the cached state (called on goal creation or explicit reset)
    static func clearCache() {
        cachedState = nil
    }

    // MARK: - Instance Properties

    /// Goal preview data (when ready to create)
    var goalDataToPreview: GoalDataPreview?

    /// Loading state during goal finalization
    var isCreatingGoal: Bool = false

    /// Conversation history for API calls (role/content pairs)
    private var conversationHistory: [(role: String, content: String)] = []

    init(client: APIClient) {
        // Check for cached state before calling super.init
        let hasCache = Self.cachedState != nil

        super.init(
            client: client,
            // Skip initial greeting if restoring from cache
            initialGreeting: hasCache ? nil : "Hi! What goal can Houston help you with?"
        )

        // Restore conversation history from cache
        if let cached = Self.cachedState {
            self.conversationHistory = cached.conversationHistory
        }
    }

    /// Restore cached messages to the view model (call after viewModel is set)
    func restoreCachedMessages() -> [ChatMessage]? {
        guard let cached = Self.cachedState else { return nil }
        return cached.messages
    }

    /// Send message and handle goal creation response
    override func sendMessage(text: String) async throws {
        // Track conversation for API
        conversationHistory.append((role: "user", content: text))

        // Build history excluding current message
        let history = conversationHistory.dropLast(1)

        // Call goal creation API (response will stream back via SSE)
        let response = try await apiClient.sendGoalCreationMessage(
            message: text,
            conversationHistory: Array(history)
        )

        // Track assistant response
        conversationHistory.append((role: "assistant", content: response.reply))

        // Check if ready to create goal
        if response.ready_to_create, let goalData = response.goal_data {
            // Wait for animation to complete
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds

            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isCreatingGoal = false
            }

            // Brief pause before showing form
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

            goalDataToPreview = GoalDataPreview(
                title: goalData.title,
                description: goalData.description,
                agentInstructions: goalData.agent_instructions,
                learnings: goalData.learnings,
                enabledMcpServers: Goal.defaultEnabledMcpServers
            )
        }
    }

    /// Get SSE stream request for goal creation
    override func streamRequest() throws -> URLRequest {
        try apiClient.goalCreationChatStreamURLRequest()
    }

    /// Handle custom SSE events (tool_call for finalize_goal_creation)
    override func handleCustomEvent(_ event: SSEClient.Event) -> Bool {
        guard let data = event.data.data(using: .utf8) else { return false }

        switch event.type {
        case .tool_call:
            // Handle finalize_goal_creation tool call
            struct ToolCall: Decodable { let tool: String }
            if let toolCall = try? JSONDecoder().decode(ToolCall.self, from: data),
               toolCall.tool == "finalize_goal_creation" {
                Task { @MainActor in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        isCreatingGoal = true
                    }
                }
                return true
            }
            return false

        default:
            return false
        }
    }

    /// Reset conversation to initial state and clear cache
    func resetConversation() {
        reset()
        conversationHistory.removeAll()
        goalDataToPreview = nil
        isCreatingGoal = false
        Self.clearCache()
    }

    /// Save current state to cache (for recovery after accidental dismiss)
    func saveToCache(messages: [ChatMessage]) {
        // Don't cache empty conversations
        guard !conversationHistory.isEmpty else { return }

        Self.cachedState = CachedState(
            conversationHistory: conversationHistory,
            messages: messages
        )
    }
}
