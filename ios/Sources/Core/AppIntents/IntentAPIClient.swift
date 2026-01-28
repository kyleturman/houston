import Foundation

// MARK: - API Response Models
// Import shared API models (defined in Core/Models/API/)
// These models are shared with APIClient and other extensions

/// Minimal API client for App Intents and Share Extension
/// Contains only the essential methods needed by extensions
/// Uses ExtensionAPIClient for networking to avoid pulling in all models
final class IntentAPIClient {
    private let core: ExtensionAPIClient

    private init(core: ExtensionAPIClient) {
        self.core = core
    }

    /// Create authenticated IntentAPIClient from App Group credentials
    static func create() throws -> IntentAPIClient {
        guard let appGroup = AppGroupConfig.shared,
              let serverURLString = appGroup.string(forKey: AppGroupConfig.serverURLKey),
              let serverURL = URL(string: serverURLString),
              let deviceToken = appGroup.string(forKey: AppGroupConfig.deviceTokenKey),
              let userToken = appGroup.string(forKey: AppGroupConfig.userTokenKey) else {
            throw IntentError.notAuthenticated
        }

        let core = ExtensionAPIClient(
            baseURL: serverURL,
            deviceTokenProvider: { deviceToken },
            userTokenProvider: { userToken }
        )

        return IntentAPIClient(core: core)
    }

    // MARK: - Goals
    // API models: GoalResource, GoalAttributes
    // Defined in: Core/Models/API/GoalAPI.swift

    func listGoals() async throws -> [GoalResource] {
        let (data, response) = try await core.request("/api/goals", auth: .user)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExtensionAPIClient.APIError.requestFailed(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }
        return try JSONDecoder().decode(JSONAPIList<GoalResource>.self, from: data).data
    }

    // MARK: - Notes
    // API models: NoteResource, NoteAttributes, NotePayload
    // Defined in: Core/Models/API/NoteAPI.swift

    func createNote(title: String?, content: String, goalId: String?) async throws -> NoteResource {
        let goalInt: Int? = goalId.flatMap { Int($0) }
        let payload = NotePayload(note: .init(title: title, content: content, goal_id: goalInt))
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await core.request("/api/notes", method: "POST", body: body, auth: .user)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExtensionAPIClient.APIError.requestFailed(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }
        return try JSONDecoder().decode(JSONAPISingle<NoteResource>.self, from: data).data
    }

    // MARK: - Agent Queries

    struct AgentQueryPayload: Encodable {
        let query: String
        let goal_id: String?
    }

    struct AgentQueryResponse: Decodable {
        let message: String
        let task_id: String?
    }

    func sendAgentQuery(query: String, goalId: String?) async throws -> AgentQueryResponse {
        let payload = AgentQueryPayload(query: query, goal_id: goalId)
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await core.request("/api/agents/query", method: "POST", body: body, auth: .user)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExtensionAPIClient.APIError.requestFailed(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }
        return try JSONDecoder().decode(AgentQueryResponse.self, from: data)
    }
}

// MARK: - Intent Errors

enum IntentError: LocalizedError {
    case notAuthenticated
    case goalNotFound
    case goalArchived
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to Houston first"
        case .goalNotFound:
            return "Goal not found"
        case .goalArchived:
            return "This goal has been archived"
        case .networkError(let message):
            return message
        }
    }
}
