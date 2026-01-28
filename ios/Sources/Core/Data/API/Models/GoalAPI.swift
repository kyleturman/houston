import Foundation

// MARK: - Goal API Models
//
// These models match the backend GoalSerializer output.
// Backend: backend/app/serializers/goal_serializer.rb
//
// JSON:API format:
// {
//   "data": {
//     "id": "123",
//     "type": "goal",
//     "attributes": {
//       "title": "My Goal",
//       "status": "working",
//       ...
//     }
//   }
// }

/// Goal resource from JSON:API response
struct GoalResource: Decodable {
    let id: String
    let type: String
    let attributes: GoalAttributes
}

/// Goal attributes from backend serializer
struct GoalAttributes: Decodable {
    let title: String
    let description: String?
    let status: String
    let accent_color: String?
    let agent_instructions: String?
    let enabled_mcp_servers: [String]?
    let active_mcp_servers_count: Int?  // Count of enabled servers that are actually available
    let learnings: [[String: String]]?
    let created_at: String?
    let updated_at: String?
    let display_order: Int?
    let llm_history: [AnyDecodable]?  // Agent execution history (not used by iOS client)
    let runtime_state: AnyDecodable?  // Agent runtime state (check-ins, follow-ups, etc.)
    let activity_level: String?       // Activity level: high, moderate, or low
    let notes_count: Int?             // Total notes count for this goal
    let tasks_count: Int?             // Active tasks count (pending, active, paused)
    let check_in_schedule: CheckInScheduleResource?  // Recurring check-in schedule
}

/// Check-in schedule from backend
struct CheckInScheduleResource: Decodable {
    let frequency: String?   // daily, weekdays, weekly, none
    let time: String?        // 24-hour format: "09:00", "14:30"
    let day_of_week: String? // For weekly: monday, tuesday, etc.
    let intent: String?      // Purpose of the check-in
}

/// Payload for creating/updating goals
struct GoalPayload: Encodable {
    let goal: Body

    struct Body: Encodable {
        let title: String
        let description: String?
        let status: String?
        let agent_instructions: String?
        let learnings: [String]?
        let enabled_mcp_servers: [String]?
        let accent_color: String?
    }
}
