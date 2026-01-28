import Foundation
import Observation

/// Base class for wizard-style chats that use client-side conversation history
/// Examples: Goal creation, task creation wizards, onboarding flows
@MainActor
@Observable
class LinearChatDataSource: ChatDataSource, @unchecked Sendable {
    /// Initial greeting message (shown once on first load)
    private let initialGreeting: String?

    /// Flag to track if initial greeting has been loaded
    private var hasLoadedInitialGreeting = false

    private let client: APIClient

    init(client: APIClient, initialGreeting: String? = nil) {
        self.client = client
        self.initialGreeting = initialGreeting
    }

    /// Load initial greeting message (only called once)
    func loadMessages() async throws -> [ChatMessage] {
        guard !hasLoadedInitialGreeting, let greeting = initialGreeting else {
            return []
        }

        hasLoadedInitialGreeting = true
        return [ChatMessage(
            id: UUID().uuidString,
            content: greeting,
            source: .agent,
            createdAt: Date()
        )]
    }

    /// Send message - subclasses should override to implement specific logic
    func sendMessage(text: String) async throws {
        // Default implementation - subclasses should override
        // Note: ChatViewModel already adds user message optimistically
        // Subclasses just need to send to the backend
    }

    /// Stream request - subclasses must implement
    func streamRequest() throws -> URLRequest {
        fatalError("Subclasses must implement streamRequest()")
    }

    /// Handle custom events - subclasses can override
    func handleCustomEvent(_ event: SSEClient.Event) -> Bool {
        return false
    }

    /// Linear chats don't show tool activities
    var showsToolActivities: Bool {
        false
    }

    /// Linear chats auto-start streaming
    var autoStartStream: Bool {
        true
    }

    /// Reset conversation to initial state
    func reset() {
        hasLoadedInitialGreeting = false
    }

    /// Get API client for subclasses
    var apiClient: APIClient {
        client
    }
}
