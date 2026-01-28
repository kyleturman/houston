import Foundation

/// Protocol defining the interface for different chat data sources
/// Allows ChatViewModel to work with both agent chats (ThreadMessages) and linear chats (conversation history)
@MainActor
protocol ChatDataSource: Sendable {
    /// Load initial messages for the chat
    func loadMessages() async throws -> [ChatMessage]

    /// Send a user message
    func sendMessage(text: String) async throws

    /// Get SSE stream request for real-time updates
    func streamRequest() throws -> URLRequest

    /// Handle custom SSE events specific to this data source
    /// Returns true if event was handled, false to use default ChatViewModel handling
    func handleCustomEvent(_ event: SSEClient.Event) -> Bool

    /// Whether to show tool activities in the chat
    var showsToolActivities: Bool { get }

    /// Whether to automatically start streaming on load
    var autoStartStream: Bool { get }
}
