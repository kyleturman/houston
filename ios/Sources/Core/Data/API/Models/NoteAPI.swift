import Foundation

// MARK: - Note API Models
//
// These models match the backend NoteSerializer output.
// Backend: backend/app/serializers/note_serializer.rb
//
// JSON:API format:
// {
//   "data": {
//     "id": "123",
//     "type": "note",
//     "attributes": {
//       "title": "Note Title",
//       "content": "Note content",
//       "goal_id": "456",  // String (not Int) per JSON:API best practice
//       ...
//     }
//   }
// }

/// Note resource from JSON:API response
struct NoteResource: Decodable {
    let id: String
    let type: String
    let attributes: NoteAttributes
}

/// Note attributes from backend serializer
struct NoteAttributes: Decodable {
    let title: String?
    let content: String?  // Can be null when note is URL-only
    let source: String
    let goal_id: String?  // Backend returns string (JSON:API best practice)
    let created_at: String?
    let updated_at: String?
    let metadata: [String: AnyCodable]?
}

/// Payload for creating/updating notes
struct NotePayload: Encodable {
    let note: Body

    struct Body: Encodable {
        let title: String?
        let content: String
        let goal_id: Int?
    }
}
