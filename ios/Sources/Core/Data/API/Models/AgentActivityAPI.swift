import Foundation

// MARK: - Agent Activity API Models
//
// Backend response models for agent execution activity tracking.
// Source: backend/app/controllers/api/agent_activities_controller.rb
//
// JSON:API format:
// {
//   "data": [
//     {
//       "id": "123",
//       "type": "agent_activity",
//       "attributes": {
//         "agent_type": "goal",
//         "agentable_type": "Goal",
//         "agentable_id": "456",
//         "goal_id": "456",
//         "input_tokens": 1000,
//         "output_tokens": 500,
//         "cost_cents": 15,
//         "cost_dollars": 0.15,
//         "formatted_cost": "$0.15",
//         "total_tokens": 1500,
//         "tool_count": 3,
//         "tools_called": ["create_note", "search_notes", "send_message"],
//         "tools_summary": "create_note, search_notes, send_message",
//         "iterations": 5,
//         "duration_seconds": 12,
//         "natural_completion": true,
//         "agent_type_label": "Goal Agent",
//         "started_at": "2025-01-05T10:00:00Z",
//         "completed_at": "2025-01-05T10:00:12Z",
//         "created_at": "2025-01-05T10:00:12Z",
//         "updated_at": "2025-01-05T10:00:12Z"
//       }
//     }
//   ],
//   "meta": {
//     "current_page": 1,
//     "per_page": 20,
//     "total_items": 50,
//     "total_pages": 3,
//     "has_next_page": true,
//     "has_prev_page": false
//   }
// }

/// Agent activity resource from backend (JSON:API format)
struct AgentActivityResource: Decodable {
    let id: String
    let type: String
    let attributes: AgentActivityAttributes
}

/// Agent activity attributes
struct AgentActivityAttributes: Decodable {
    let agent_type: String
    let agentable_type: String
    let agentable_id: String
    let goal_id: String?
    let input_tokens: Int
    let output_tokens: Int
    let cost_cents: Int
    let cost_dollars: Double
    let formatted_cost: String
    let total_tokens: Int
    let tool_count: Int
    let tools_called: [String]
    let tools_summary: String
    let iterations: Int
    let duration_seconds: Int
    let natural_completion: Bool
    let agent_type_label: String
    let started_at: String
    let completed_at: String
    let created_at: String
    let updated_at: String
}

/// Paginated response for agent activities
struct AgentActivityListResponse: Decodable {
    let data: [AgentActivityResource]
    let meta: PaginationMeta
}

/// Pagination metadata
struct PaginationMeta: Decodable {
    let current_page: Int
    let per_page: Int
    let total_items: Int
    let total_pages: Int
    let has_next_page: Bool
    let has_prev_page: Bool
}
