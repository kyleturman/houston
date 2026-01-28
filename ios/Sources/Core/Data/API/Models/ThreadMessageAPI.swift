import Foundation

// MARK: - Thread Message API Models
//
// Models for goal, task, and user agent thread messages.
// Used for chat/conversation history with agents.

/// Thread message resource (JSON:API format)
struct ThreadMessageResource: Decodable, Sendable {
    let id: String
    let type: String
    let attributes: ThreadMessageAttributes
}

/// Thread message attributes
struct ThreadMessageAttributes: Decodable, Sendable {
    let content: String
    let source: String
    let goal_id: String?
    let agent_task_id: String?
    let agent_history_id: String?
    let created_at: String?
    let updated_at: String?
    let metadata: [String: AnyDecodable]?
}

/// Paginated response for thread messages with session metadata
struct ThreadMessagePaginatedResponse: Decodable {
    let data: [ThreadMessageResource]
    let meta: SessionPaginationMeta
}

/// Payload for creating a thread message
struct ThreadMessagePayload: Encodable {
    let message: String
}
