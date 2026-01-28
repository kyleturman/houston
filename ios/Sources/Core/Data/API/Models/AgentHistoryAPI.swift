import Foundation

// MARK: - Agent History API Models
//
// Models for agent execution histories (sessions).
// Used for tracking past agent runs and their summaries.

// MARK: - Agent History Resource

/// Agent history resource (JSON:API format)
struct AgentHistoryResource: Decodable, Sendable {
    let id: String
    let type: String
    let attributes: AgentHistoryAttributes
}

/// Agent history attributes
struct AgentHistoryAttributes: Decodable, Sendable {
    let summary: String
    let completion_reason: String?
    let message_count: Int?
    let token_count: Int?
    let agentable_type: String
    let agentable_id: String
    let started_at: String?
    let completed_at: String?  // Nullable for current session
    let created_at: String?    // Nullable for current session
    let updated_at: String?    // Nullable for current session
    let is_current: Bool?      // True for current (in-progress) session
}

// MARK: - Response Wrappers

/// Response wrapper for agent history list
struct AgentHistoryResponse: Decodable, Sendable {
    let data: [AgentHistoryResource]
}

/// Response wrapper for agent history detail (includes thread messages)
struct AgentHistoryDetailResponse: Decodable, Sendable {
    let data: AgentHistoryResource
    let included: AgentHistoryIncluded?
}

/// Included resources in agent history detail response
struct AgentHistoryIncluded: Decodable, Sendable {
    let thread_messages: [ThreadMessageResource]?
}

// MARK: - Pagination

/// Pagination metadata for session-based pagination
struct SessionPaginationMeta: Decodable, Sendable {
    let total_sessions: Int
    let loaded_sessions: Int
    let has_more: Bool
}
