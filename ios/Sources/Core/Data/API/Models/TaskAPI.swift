import Foundation

// MARK: - Agent Task API Models
//
// These models match the backend AgentTaskSerializer output.
// Backend: backend/app/serializers/agent_task_serializer.rb
//
// JSON:API format:
// {
//   "data": {
//     "id": "123",
//     "type": "agent_task",
//     "attributes": {
//       "title": "Task Title",
//       "status": "pending",
//       "goal_id": "456",  // String (backend uses string_id_attribute)
//       ...
//     }
//   }
// }

/// Agent task resource from JSON:API response
struct AgentTaskResource: Decodable {
    let id: String
    let type: String
    let attributes: AgentTaskAttributes
}

/// Agent task attributes from backend serializer
struct AgentTaskAttributes: Decodable {
    let title: String
    let instructions: String?
    let status: String
    let priority: String
    let goal_id: String?  // Backend returns string (JSON:API best practice)
    let created_at: String?
    let updated_at: String?
    let error_type: String?
    let error_message: String?
    let retry_count: Int?
    let next_retry_at: String?
    let cancelled_reason: String?
    let llm_history: [AnyDecodable]?  // Agent execution history
}
