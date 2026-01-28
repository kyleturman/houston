import Foundation

/// Data source for persistent agent chats (goals, tasks, user agent)
/// Uses ThreadMessage API for server-side persistence and tool activities
class AgentChatDataSource: ChatDataSource, @unchecked Sendable {
    /// Agent chat context (goal, task, or user agent)
    enum Context: Equatable, Sendable {
        case goal(id: String)
        case task(id: String)
        case userAgent
    }

    let context: Context
    private let client: APIClient

    init(context: Context, client: APIClient) {
        self.context = context
        self.client = client
    }

    /// Internal pagination state
    private var paginationMeta: SessionPaginationMeta?
    private var sessionCount: Int?

    func loadMessages() async throws -> [ChatMessage] {
        let resources: [ThreadMessageResource]
        let meta: SessionPaginationMeta?

        switch context {
        case .goal(let id):
            (resources, meta) = try await client.listGoalThreadMessages(goalId: id, sessionCount: sessionCount)
        case .task(let id):
            resources = try await client.listTaskThreadMessages(taskId: id)
            meta = nil
        case .userAgent:
            (resources, meta) = try await client.listUserAgentThreadMessages(sessionCount: sessionCount)
        }

        // Store pagination meta for later use
        self.paginationMeta = meta

        return resources.map { ChatMessage(from: $0) }
    }

    /// Load messages with specific session count (for pagination)
    func loadMessages(sessionCount: Int) async throws -> (messages: [ChatMessage], meta: SessionPaginationMeta?) {
        self.sessionCount = sessionCount

        let resources: [ThreadMessageResource]
        let meta: SessionPaginationMeta?

        switch context {
        case .goal(let id):
            (resources, meta) = try await client.listGoalThreadMessages(goalId: id, sessionCount: sessionCount)
        case .task(let id):
            resources = try await client.listTaskThreadMessages(taskId: id)
            meta = nil
        case .userAgent:
            (resources, meta) = try await client.listUserAgentThreadMessages(sessionCount: sessionCount)
        }

        self.paginationMeta = meta
        return (messages: resources.map { ChatMessage(from: $0) }, meta: meta)
    }

    /// Get current pagination meta
    func getPaginationMeta() -> SessionPaginationMeta? {
        return paginationMeta
    }

    func sendMessage(text: String) async throws {
        switch context {
        case .goal(let id):
            _ = try await client.createGoalThreadMessage(goalId: id, message: text)
        case .task(let id):
            _ = try await client.createTaskThreadMessage(taskId: id, message: text)
        case .userAgent:
            _ = try await client.createUserAgentThreadMessage(message: text)
        }
    }

    func streamRequest() throws -> URLRequest {
        switch context {
        case .goal(let id):
            return try client.threadStreamURLRequest(goalId: id)
        case .task(let id):
            return try client.threadStreamURLRequest(taskId: id)
        case .userAgent:
            return try client.threadStreamURLRequest()
        }
    }

    func handleCustomEvent(_ event: SSEClient.Event) -> Bool {
        // Use default ChatViewModel event handling
        return false
    }

    var showsToolActivities: Bool {
        true
    }

    var autoStartStream: Bool {
        true
    }
}
