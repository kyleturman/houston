import Foundation

struct AgentHistory: Identifiable, Sendable, Equatable {
    let id: String
    let summary: String
    let completionReason: String?
    let messageCount: Int
    let tokenCount: Int
    let agentableType: String
    let agentableId: String
    let startedAt: Date?
    let completedAt: Date?  // Nullable for current session
    let createdAt: Date?    // Nullable for current session
    let updatedAt: Date?    // Nullable for current session
    let isCurrent: Bool     // True for current (in-progress) session

    var sessionDateString: String {
        guard let date = completedAt else {
            return "In Progress"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var sessionDateOnly: String {
        guard let date = completedAt else {
            return "In Progress"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func from(resource: AgentHistoryResource) -> AgentHistory {
        let formatter = ISO8601DateFormatter()

        return AgentHistory(
            id: resource.id,
            summary: resource.attributes.summary,
            completionReason: resource.attributes.completion_reason,
            messageCount: resource.attributes.message_count ?? 0,
            tokenCount: resource.attributes.token_count ?? 0,
            agentableType: resource.attributes.agentable_type,
            agentableId: resource.attributes.agentable_id,
            startedAt: resource.attributes.started_at.flatMap { formatter.date(from: $0) },
            completedAt: resource.attributes.completed_at.flatMap { formatter.date(from: $0) },
            createdAt: resource.attributes.created_at.flatMap { formatter.date(from: $0) },
            updatedAt: resource.attributes.updated_at.flatMap { formatter.date(from: $0) },
            isCurrent: resource.attributes.is_current ?? false
        )
    }
}
