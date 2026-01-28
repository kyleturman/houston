import Foundation

// MARK: - User Agent API Models
//
// Models for the user agent - the persistent assistant that manages goals.
// Includes learnings, goal creation chat, and shortcuts/Siri queries.

// MARK: - User Agent Resource

/// User agent resource (JSON:API format)
struct UserAgentResource: Decodable, Sendable {
    let id: String
    let type: String
    let attributes: UserAgentAttributes
}

/// User agent attributes
struct UserAgentAttributes: Decodable, Sendable {
    let learnings: [[String: String]]?
    let created_at: String
    let updated_at: String
}

/// Response wrapper for user agent
struct UserAgentResponse: Decodable, Sendable {
    let data: UserAgentResource
}

// MARK: - Goal Creation Chat

/// Request for goal creation chat
struct GoalCreationChatRequest: Encodable {
    let message: String
    let conversation_history: [ConversationMessage]

    struct ConversationMessage: Encodable {
        let role: String
        let content: String
    }
}

/// Response from goal creation chat
struct GoalCreationChatResponse: Decodable {
    let reply: String
    let ready_to_create: Bool
    let goal_data: GoalData?

    struct GoalData: Decodable {
        let title: String
        let description: String
        let agent_instructions: String
        let learnings: [String]
    }
}

// MARK: - Shortcuts / Siri Agent Query

/// Payload for agent query from Siri/Shortcuts
struct AgentQueryPayload: Encodable {
    let query: String
    let goal_id: String?
}

/// Response from agent query
struct AgentQueryResponse: Decodable {
    let success: Bool
    let message: String
    let task_id: String
    let goal_id: String?
}
