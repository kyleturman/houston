import Foundation
import UIKit

// MARK: - API Response Models
// Import shared API models (defined in Core/Models/API/)
// These models are shared with IntentAPIClient for extensions

final class APIClient: @unchecked Sendable {
    enum APIError: LocalizedError {
        case invalidURL
        case requestFailed(statusCode: Int?, message: String?)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .requestFailed(_, let message):
                if let message = message,
                   let data = message.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    return error
                }
                return message ?? "Request failed"
            case .decodingFailed:
                return "Failed to decode response"
            }
        }
    }
    enum AuthContext { case none, device, user }

    private let baseURL: URL
    private let deviceTokenProvider: () -> String?
    private let userTokenProvider: () -> String?
    private let session: URLSession
    private let cacheManager: APICacheManager

    init(baseURL: URL, deviceTokenProvider: @escaping () -> String?, userTokenProvider: @escaping () -> String? = { nil }) {
        self.baseURL = baseURL
        self.deviceTokenProvider = deviceTokenProvider
        self.userTokenProvider = userTokenProvider

        // Initialize URLSession with enhanced configuration
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false  // Don't wait - fail fast and use cache fallback
        config.timeoutIntervalForRequest = 10  // Fail fast - 10s timeout
        config.timeoutIntervalForResource = 300  // 5 minutes for long operations
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)

        // Initialize cache manager
        self.cacheManager = APICacheManager(userTokenProvider: userTokenProvider)
    }

    // (Removed Activity Log endpoints; use llm_history returned on goal/task resources)

    // MARK: - Notes (User-scoped)
    // API models: NoteResource, NoteAttributes, NotePayload
    // Defined in: Core/Models/API/NoteAPI.swift

    func listNotes(goalId: String) async throws -> [NoteResource] {
        let (data, response) = try await request("/api/goals/\(goalId)/notes", auth: .user)
        return try validateAndDecode(JSONAPICursorPaginatedList<NoteResource>.self, from: data, response: response).data
    }

    /// List notes with cursor-based pagination
    /// - Parameters:
    ///   - goalId: The goal ID to filter notes
    ///   - beforeId: Cursor for pagination - fetch notes older than this ID
    ///   - perPage: Number of notes per page (default 20, max 100)
    /// - Returns: Tuple of notes and pagination metadata
    func listNotesPaginated(goalId: String, beforeId: String? = nil, perPage: Int = 20) async throws -> (notes: [NoteResource], meta: CursorPaginationMeta) {
        var path = "/api/goals/\(goalId)/notes?per_page=\(perPage)"
        if let beforeId = beforeId {
            path += "&before_id=\(beforeId)"
        }

        let (data, response) = try await request(path, auth: .user)
        let paginatedResponse = try validateAndDecode(JSONAPICursorPaginatedList<NoteResource>.self, from: data, response: response)
        return (notes: paginatedResponse.data, meta: paginatedResponse.meta)
    }

    func listAllNotes() async throws -> [NoteResource] {
        let (data, response) = try await request("/api/notes", auth: .user)
        return try validateAndDecode(JSONAPICursorPaginatedList<NoteResource>.self, from: data, response: response).data
    }

    func createNote(title: String?, content: String, goalId: String?) async throws -> NoteResource {
        let goalInt: Int? = goalId.flatMap { Int($0) }
        let payload = NotePayload(note: .init(title: title, content: content, goal_id: goalInt))
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await request("/api/notes", method: "POST", body: body, auth: .user)
        let note = try validateAndDecode(JSONAPISingle<NoteResource>.self, from: data, response: response).data
        invalidateRelatedCaches(forResourceType: "note", resourceId: note.id, action: "created")
        return note
    }

    func updateNote(id: String, title: String?, content: String, goalId: String?) async throws -> NoteResource {
        let goalInt: Int? = goalId.flatMap { Int($0) }
        let payload = NotePayload(note: .init(title: title, content: content, goal_id: goalInt))
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await request("/api/notes/\(id)", method: "PATCH", body: body, auth: .user)
        let note = try validateAndDecode(JSONAPISingle<NoteResource>.self, from: data, response: response).data
        invalidateRelatedCaches(forResourceType: "note", resourceId: id, action: "updated")
        return note
    }

    func getNote(id: String) async throws -> NoteResource {
        let (data, response) = try await request("/api/notes/\(id)", auth: .user)
        return try validateAndDecode(JSONAPISingle<NoteResource>.self, from: data, response: response).data
    }

    func deleteNote(id: String) async throws {
        let (data, response) = try await request("/api/notes/\(id)", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
        invalidateRelatedCaches(forResourceType: "note", resourceId: id, action: "deleted")
    }

    func retryNoteProcessing(id: String) async throws {
        let (data, response) = try await request("/api/notes/\(id)/retry_processing", method: "POST", auth: .user)
        _ = try validateResponse(data, response)
    }

    func ignoreNoteProcessing(id: String) async throws {
        let (data, response) = try await request("/api/notes/\(id)/ignore_processing", method: "POST", auth: .user)
        _ = try validateResponse(data, response)
    }

    func dismissNote(id: String) async throws {
        let (data, response) = try await request("/api/notes/\(id)/dismiss", method: "POST", auth: .user)
        _ = try validateResponse(data, response)
    }

    // MARK: - Goals (User-scoped)
    // API models: GoalResource, GoalAttributes, GoalPayload
    // Defined in: Core/Models/API/GoalAPI.swift

    func listGoals() async throws -> [GoalResource] {
        let (data, response) = try await request("/api/goals", auth: .user)
        return try validateAndDecode(JSONAPIList<GoalResource>.self, from: data, response: response).data
    }

    func getGoal(id: String) async throws -> GoalResource {
        let (data, response) = try await request("/api/goals/\(id)", auth: .user)
        return try validateAndDecode(JSONAPISingle<GoalResource>.self, from: data, response: response).data
    }

    func createGoal(title: String, description: String?, status: String? = nil, agentInstructions: String? = nil, learnings: [String]? = nil, enabledMcpServers: [String]? = nil, accentColor: String? = nil) async throws -> GoalResource {
        let payload = GoalPayload(goal: .init(title: title, description: description, status: status, agent_instructions: agentInstructions, learnings: learnings, enabled_mcp_servers: enabledMcpServers, accent_color: accentColor))
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await request("/api/goals", method: "POST", body: body, auth: .user)
        let goal = try validateAndDecode(JSONAPISingle<GoalResource>.self, from: data, response: response).data
        invalidateRelatedCaches(forResourceType: "goal", resourceId: goal.id, action: "created")
        return goal
    }

    func updateGoal(id: String, title: String? = nil, description: String? = nil, status: String? = nil, agentInstructions: String? = nil, learnings: [String]? = nil, enabledMcpServers: [String]? = nil, accentColor: String? = nil) async throws -> GoalResource {
        // Build the payload manually to include all optional fields
        var goalDict: [String: Any] = [:]
        
        if let title = title {
            goalDict["title"] = title
        }
        if let status = status {
            goalDict["status"] = status
        }
        if let desc = description {
            goalDict["description"] = desc
        }
        if let instructions = agentInstructions {
            goalDict["agent_instructions"] = instructions
        }
        if let learnings = learnings {
            goalDict["learnings"] = learnings
        }
        if let servers = enabledMcpServers {
            goalDict["enabled_mcp_servers"] = servers
        }
        if let color = accentColor {
            goalDict["accent_color"] = color
        }
        
        let payload = ["goal": goalDict]
        let body = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await request("/api/goals/\(id)", method: "PATCH", body: body, auth: .user)
        let goal = try validateAndDecode(JSONAPISingle<GoalResource>.self, from: data, response: response).data
        invalidateRelatedCaches(forResourceType: "goal", resourceId: id, action: "updated")
        return goal
    }

    func deleteGoal(id: String) async throws {
        let (data, response) = try await request("/api/goals/\(id)", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
        invalidateRelatedCaches(forResourceType: "goal", resourceId: id, action: "deleted")
    }

    func resetGoalAgent(id: String) async throws -> Bool {
        let (data, response) = try await request("/api/goals/\(id)/agent_reset", method: "POST", auth: .user)
        _ = try validateResponse(data, response)
        return true
    }

    func reorderGoals(goalIds: [String]) async throws {
        let payload = ["goal_ids": goalIds]
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await request("/api/goals/reorder", method: "POST", body: body, auth: .user)
        _ = try validateResponse(data, response)
    }

    func resetUserAgent() async throws -> Bool {
        let (data, response) = try await request("/api/user_agent/reset", method: "POST", auth: .user)
        _ = try validateResponse(data, response)
        return true
    }

    // MARK: - User Agent Update
    // API models: UserAgentResource, UserAgentAttributes, UserAgentResponse
    // Defined in: Core/Data/API/Models/UserAgentAPI.swift

    func getUserAgent() async throws -> UserAgentResource {
        let (data, response) = try await request("/api/user_agent", auth: .user)
        return try validateAndDecode(UserAgentResponse.self, from: data, response: response).data
    }

    func updateUserAgent(learnings: [String]) async throws -> UserAgentResource {
        let payload: [String: Any] = ["user_agent": ["learnings": learnings]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await request("/api/user_agent", method: "PATCH", body: body, auth: .user)
        return try validateAndDecode(UserAgentResponse.self, from: data, response: response).data
    }

    // MARK: - Goal Creation Chat
    // API models: GoalCreationChatRequest, GoalCreationChatResponse
    // Defined in: Core/Data/API/Models/UserAgentAPI.swift

    func sendGoalCreationMessage(message: String, conversationHistory: [(role: String, content: String)]) async throws -> GoalCreationChatResponse {
        let history = conversationHistory.map { GoalCreationChatRequest.ConversationMessage(role: $0.role, content: $0.content) }
        let payload = GoalCreationChatRequest(message: message, conversation_history: history)
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await request("/api/goal_creation_chat/message", method: "POST", body: body, auth: .user)
        return try validateAndDecode(GoalCreationChatResponse.self, from: data, response: response)
    }
    
    // MARK: - SSE Streaming Endpoints
    // All streaming endpoints use authorizedStreamRequest() for consistent auth and headers
    
    func goalCreationChatStreamURLRequest() throws -> URLRequest {
        return try authorizedStreamRequest(path: "/api/goal_creation_chat/stream", auth: .user)
    }

    // MARK: - Agent Tasks
    // API models: AgentTaskResource, AgentTaskAttributes
    // Defined in: Core/Models/API/TaskAPI.swift

    func listGoalTasks(goalId: String) async throws -> [AgentTaskResource] {
        let (data, response) = try await request("/api/goals/\(goalId)/agent_tasks", auth: .user)
        return try validateAndDecode(JSONAPIList<AgentTaskResource>.self, from: data, response: response).data
    }

    func getTask(id: String) async throws -> AgentTaskResource {
        let (data, response) = try await request("/api/agent_tasks/\(id)", auth: .user)
        return try validateAndDecode(JSONAPISingle<AgentTaskResource>.self, from: data, response: response).data
    }
    
    func retryTask(taskId: String) async throws -> AgentTaskResource {
        let (data, response) = try await request("/api/agent_tasks/\(taskId)/retry", method: "POST", auth: .user)
        let task = try validateAndDecode(JSONAPISingle<AgentTaskResource>.self, from: data, response: response).data
        invalidateRelatedCaches(forResourceType: "task", resourceId: taskId, action: "updated")
        return task
    }

    // MARK: - Agent Activities
    // API models: AgentActivityResource, AgentActivityAttributes, PaginationMeta
    // Defined in: Core/Data/API/AgentActivityAPI.swift

    func listAgentActivities(page: Int = 1, perPage: Int = 20, agentType: String? = nil, goalId: String? = nil) async throws -> (activities: [AgentActivityResource], meta: PaginationMeta) {
        var queryItems: [String] = ["page=\(page)", "per_page=\(perPage)"]
        if let agentType = agentType { queryItems.append("agent_type=\(agentType)") }
        if let goalId = goalId { queryItems.append("goal_id=\(goalId)") }
        let path = "/api/agent_activities?\(queryItems.joined(separator: "&"))"

        let (data, response) = try await request(path, auth: .user)
        let listResponse = try validateAndDecode(AgentActivityListResponse.self, from: data, response: response)
        return (activities: listResponse.data, meta: listResponse.meta)
    }

    func getAgentActivity(id: String) async throws -> AgentActivityResource {
        let (data, response) = try await request("/api/agent_activities/\(id)", auth: .user)
        return try validateAndDecode(JSONAPISingle<AgentActivityResource>.self, from: data, response: response).data
    }

    // MARK: - Health Check (no auth required)
    func up() async throws -> Bool {
        let (data, response) = try await request("/up", auth: .none)
        _ = try validateResponse(data, response)
        return true
    }

    // MARK: - Cache (delegated to APICacheManager)

    func clearAllCache() { cacheManager.clearAllCache() }
    func clearCacheForPath(_ path: String, auth: AuthContext = .user) { cacheManager.clearCacheForPath(path) }
    func clearCachesMatchingPattern(_ pattern: String, auth: AuthContext = .user) { cacheManager.clearCachesMatchingPattern(pattern) }
    func invalidateRelatedCaches(forResourceType resourceType: String, resourceId: String, action: String) {
        cacheManager.invalidateRelatedCaches(forResourceType: resourceType, resourceId: resourceId, action: action)
    }
    func loadFromCacheOnly(path: String, auth: AuthContext = .user) async -> Data? {
        await cacheManager.loadFromCacheOnly(path: path)
    }

    // MARK: - Network Requests

    /// Network-first request with offline cache fallback
    ///
    /// Cache Strategy for Cache-Then-Network Pattern:
    /// 1. ViewModel calls loadFromCacheOnly() first → Shows instant UI
    /// 2. ViewModel calls this method → Fetches fresh data from server
    /// 3. If network fails → Falls back to cache
    ///
    /// This ensures:
    /// - Instant UI (cache loaded separately by ViewModel)
    /// - Fresh data (always fetches from server)
    /// - Offline support (cache fallback when network fails)
    ///
    /// Uses custom URLSession with waitsForConnectivity and better error handling
    private func request(_ path: String, method: String = "GET", body: Data? = nil, auth: AuthContext = .device, timeout: TimeInterval = 60) async throws -> (Data, URLResponse) {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        applyAuth(&req, auth: auth)
        if let body = body {
            req.httpBody = body
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: req)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                checkForDeviceRevocation(data: data)
            }

            // Cache successful GET responses
            if method == "GET", let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) {
                let key = cacheManager.cacheKey(for: path)
                cacheManager.cacheResponse(data, key: key)
            }

            return (data, response)
        } catch {
            // Offline fallback: try cache for failed GET requests
            if method == "GET" {
                let key = cacheManager.cacheKey(for: path)
                if let cached = await cacheManager.loadCachedResponse(key: key) {
                    APILogger.debug("Network failed, using cached data (offline fallback)")
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["X-From-Cache": "true", "X-Offline-Fallback": "true"])!
                    return (cached, response)
                }
            }
            throw error
        }
    }

    /// Check if the error response indicates device token was revoked
    /// If so, clear all cache and notify session manager to sign out
    private func checkForDeviceRevocation(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String,
              error == "device_token_revoked" else {
            return
        }

        APILogger.error("Device token revoked - clearing cache and signing out")

        // Clear all cached data
        clearAllCache()

        // Notify session to sign out device (will route to landing/login)
        Task { @MainActor in
            // Get session manager from environment and trigger sign out
            // Note: We can't directly access SessionManager here, so we'll let
            // the calling code handle 401 errors appropriately
            // This method just clears the cache as a safety measure
        }
    }

    // MARK: - SSE Streaming Helper
    
    /// Creates a properly configured URLRequest for SSE streaming endpoints.
    /// 
    /// This helper ensures all streaming requests have:
    /// - Proper authentication (device or user token)
    /// - Correct Accept header for SSE (text/event-stream)
    /// - Infinite timeout for long-lived connections
    ///
    /// **Always use this for SSE endpoints** to ensure consistent auth and headers.
    ///
    /// - Parameters:
    ///   - path: The API path (e.g., "/api/goals/:id/thread/stream")
    ///   - auth: Authentication context (.device or .user)
    /// - Returns: Configured URLRequest ready for SSEClient
    private func authorizedStreamRequest(path: String, auth: AuthContext = .device) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        applyAuth(&req, auth: auth)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 0 // keep open for streaming
        return req
    }

    private func applyAuth(_ req: inout URLRequest, auth: AuthContext) {
        // Add timezone header (inferred from device)
        req.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")

        // Skip ngrok browser warning page (required for free tier tunnels)
        req.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")

        switch auth {
        case .none:
            break
        case .device:
            if let token = deviceTokenProvider() {
                req.setValue("Device \(token)", forHTTPHeaderField: "Authorization")
            }
        case .user:
            if let userToken = userTokenProvider() {
                req.setValue("User \(userToken)", forHTTPHeaderField: "Authorization")
            }
        }
    }

    // MARK: - Auth: Magic Link / Invite Token Claim
    // API models: MagicClaimResponse
    // Defined in: Core/Data/API/Models/AuthResponseAPI.swift

    @MainActor
    func claimMagicLink(token: String, deviceName: String? = nil) async throws -> MagicClaimResponse {
        let payload: [String: Any] = ["token": token, "device_name": deviceName ?? UIDevice.current.name, "platform": "iOS"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let (respData, response) = try await request("/api/auth/magic_links/claim", method: "POST", body: data, auth: .none)
        return try validateAndDecode(MagicClaimResponse.self, from: respData, response: response)
    }

    @MainActor
    func claimInviteToken(email: String, token: String, deviceName: String? = nil) async throws -> MagicClaimResponse {
        let payload: [String: Any] = ["email": email, "token": token, "device_name": deviceName ?? UIDevice.current.name, "platform": "iOS"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let (respData, response) = try await request("/api/auth/invite_tokens/claim", method: "POST", body: data, auth: .none)
        return try validateAndDecode(MagicClaimResponse.self, from: respData, response: response)
    }

    // MARK: - Auth: Request Sign-in Link
    // API models: RequestSigninResponse
    // Defined in: Core/Data/API/Models/AuthResponseAPI.swift

    @MainActor
    func requestSignin(email: String) async throws -> RequestSigninResponse {
        let payload: [String: Any] = ["email": email]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let (respData, response) = try await request("/api/auth/request_signin", method: "POST", body: data, auth: .none)
        return try validateAndDecode(RequestSigninResponse.self, from: respData, response: response)
    }

    // MARK: - Ping (authenticated device check)
    // API models: PingResponse
    // Defined in: Core/Data/API/Models/AuthResponseAPI.swift

    func ping() async throws -> Bool {
        let (data, response) = try await request("/api/ping", auth: .device)
        return try validateAndDecode(PingResponse.self, from: data, response: response).ok
    }

    // MARK: - User Auth (Passwordless - Magic Links Only)
    // API models: TokenRefreshResponse
    // Defined in: Core/Data/API/Models/AuthResponseAPI.swift

    func refreshToken() async throws -> TokenRefreshResponse {
        let (data, response) = try await request("/api/auth/refresh", method: "POST", auth: .user)
        return try validateAndDecode(TokenRefreshResponse.self, from: data, response: response)
    }

    // MARK: - User Profile
    // API models: UserProfileResponse
    // Defined in: Core/Data/API/Models/AuthResponseAPI.swift

    func getUserProfile() async throws -> UserProfileResponse {
        let (data, response) = try await request("/api/user/profile", auth: .user)
        return try validateAndDecode(UserProfileResponse.self, from: data, response: response)
    }

    func updateUserProfile(name: String, email: String? = nil) async throws -> UserProfileResponse {
        var payload: [String: Any] = ["name": name]
        if let email = email { payload["email"] = email }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let (respData, response) = try await request("/api/user/profile", method: "PATCH", body: data, auth: .user)
        return try validateAndDecode(UserProfileResponse.self, from: respData, response: response)
    }

    func completeOnboarding() async throws -> UserProfileResponse {
        let payload: [String: Any] = ["onboarding_completed": true]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let (respData, response) = try await request("/api/user/profile", method: "PATCH", body: data, auth: .user)
        return try validateAndDecode(UserProfileResponse.self, from: respData, response: response)
    }

    // MARK: - Shortcuts/App Intents
    // API models: AgentQueryPayload, AgentQueryResponse
    // Defined in: Core/Data/API/Models/UserAgentAPI.swift

    func sendAgentQuery(query: String, goalId: String?) async throws -> AgentQueryResponse {
        let payload = AgentQueryPayload(query: query, goal_id: goalId)
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await request("/api/shortcuts/agent_query", method: "POST", body: body, auth: .user)
        return try validateAndDecode(AgentQueryResponse.self, from: data, response: response)
    }

    // MARK: - Thread Messages
    // API models: ThreadMessageResource, ThreadMessageAttributes, ThreadMessagePaginatedResponse, ThreadMessagePayload
    // Defined in: Core/Data/API/Models/ThreadMessageAPI.swift

    func listGoalThreadMessages(goalId: String, sessionCount: Int? = nil) async throws -> (messages: [ThreadMessageResource], meta: SessionPaginationMeta?) {
        var path = "/api/goals/\(goalId)/thread/messages"
        if let sessionCount = sessionCount { path += "?session_count=\(sessionCount)" }

        let (data, response) = try await request(path, auth: .user)
        _ = try validateResponse(data, response)

        if sessionCount != nil {
            let paginatedResponse = try validateAndDecode(ThreadMessagePaginatedResponse.self, from: data, response: response)
            return (messages: paginatedResponse.data, meta: paginatedResponse.meta)
        } else {
            let messages = try validateAndDecode(JSONAPIList<ThreadMessageResource>.self, from: data, response: response).data
            return (messages: messages, meta: nil)
        }
    }

    func listTaskThreadMessages(taskId: String) async throws -> [ThreadMessageResource] {
        let (data, response) = try await request("/api/agent_tasks/\(taskId)/thread/messages", auth: .user)
        return try validateAndDecode(JSONAPIList<ThreadMessageResource>.self, from: data, response: response).data
    }

    func createGoalThreadMessage(goalId: String, message: String) async throws -> Bool {
        let body = try JSONEncoder().encode(ThreadMessagePayload(message: message))
        let (data, response) = try await request("/api/goals/\(goalId)/thread/messages", method: "POST", body: body, auth: .user)
        _ = try validateResponse(data, response)
        invalidateRelatedCaches(forResourceType: "thread_message", resourceId: goalId, action: "created")
        return true
    }

    func createTaskThreadMessage(taskId: String, message: String) async throws -> Bool {
        let body = try JSONEncoder().encode(ThreadMessagePayload(message: message))
        let (data, response) = try await request("/api/agent_tasks/\(taskId)/thread/messages", method: "POST", body: body, auth: .user)
        _ = try validateResponse(data, response)
        invalidateRelatedCaches(forResourceType: "thread_message", resourceId: taskId, action: "created")
        return true
    }

    func threadStreamURLRequest(goalId: String) throws -> URLRequest {
        return try authorizedStreamRequest(path: "/api/goals/\(goalId)/thread/messages/stream", auth: .user)
    }

    func threadStreamURLRequest(taskId: String) throws -> URLRequest {
        return try authorizedStreamRequest(path: "/api/agent_tasks/\(taskId)/thread/messages/stream", auth: .user)
    }

    // MARK: - User Agent Thread Messages

    func listUserAgentThreadMessages(sessionCount: Int? = nil) async throws -> (messages: [ThreadMessageResource], meta: SessionPaginationMeta?) {
        var path = "/api/user_agent/thread/messages"
        if let sessionCount = sessionCount { path += "?session_count=\(sessionCount)" }

        let (data, response) = try await request(path, auth: .user)
        _ = try validateResponse(data, response)

        if sessionCount != nil {
            let paginatedResponse = try validateAndDecode(ThreadMessagePaginatedResponse.self, from: data, response: response)
            return (messages: paginatedResponse.data, meta: paginatedResponse.meta)
        } else {
            let messages = try validateAndDecode(JSONAPIList<ThreadMessageResource>.self, from: data, response: response).data
            return (messages: messages, meta: nil)
        }
    }
    
    func createUserAgentThreadMessage(message: String) async throws -> Bool {
        let body = try JSONEncoder().encode(ThreadMessagePayload(message: message))
        let (data, response) = try await request("/api/user_agent/thread/messages", method: "POST", body: body, auth: .user)
        _ = try validateResponse(data, response)
        invalidateRelatedCaches(forResourceType: "thread_message", resourceId: "user_agent", action: "created")
        return true
    }
    
    func threadStreamURLRequest() throws -> URLRequest {
        return try authorizedStreamRequest(path: "/api/user_agent/thread/messages/stream", auth: .user)
    }

    // MARK: - Error Message Actions (Retry/Dismiss)

    func retryErrorMessage(messageId: String) async throws -> [String] {
        struct RetryResponse: Decodable { let success: Bool; let retried_message_ids: [String]? }
        let (data, response) = try await request("/api/thread_messages/\(messageId)/retry", method: "POST", auth: .user)
        let result = try validateAndDecode(RetryResponse.self, from: data, response: response)
        return result.retried_message_ids ?? []
    }

    func dismissErrorMessage(messageId: String) async throws {
        let (data, response) = try await request("/api/thread_messages/\(messageId)", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
    }

    // MARK: - Agent Histories (Goals)

    func listGoalAgentHistories(goalId: String) async throws -> [AgentHistoryResource] {
        let (data, response) = try await request("/api/goals/\(goalId)/agent_histories", auth: .user)
        return try validateAndDecode(AgentHistoryResponse.self, from: data, response: response).data
    }

    func getGoalAgentHistory(goalId: String, historyId: String) async throws -> (history: AgentHistoryResource, messages: [ThreadMessageResource]) {
        let (data, response) = try await request("/api/goals/\(goalId)/agent_histories/\(historyId)", auth: .user)
        let detailResponse = try validateAndDecode(AgentHistoryDetailResponse.self, from: data, response: response)
        return (history: detailResponse.data, messages: detailResponse.included?.thread_messages ?? [])
    }

    func deleteGoalAgentHistory(goalId: String, historyId: String) async throws {
        let (data, response) = try await request("/api/goals/\(goalId)/agent_histories/\(historyId)", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
        invalidateRelatedCaches(forResourceType: "agent_history", resourceId: historyId, action: "deleted")
    }

    func getGoalCurrentSession(goalId: String) async throws -> (history: AgentHistoryResource, messages: [ThreadMessageResource]) {
        let (data, response) = try await request("/api/goals/\(goalId)/agent_histories/current", auth: .user)
        let detailResponse = try validateAndDecode(AgentHistoryDetailResponse.self, from: data, response: response)
        return (history: detailResponse.data, messages: detailResponse.included?.thread_messages ?? [])
    }

    func resetGoalCurrentSession(goalId: String) async throws {
        let (data, response) = try await request("/api/goals/\(goalId)/agent_histories/current", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
        invalidateRelatedCaches(forResourceType: "agent_history", resourceId: "current", action: "reset")
    }

    // MARK: - Agent Histories (User Agent)

    func listUserAgentHistories() async throws -> [AgentHistoryResource] {
        let (data, response) = try await request("/api/user_agent/agent_histories", auth: .user)
        return try validateAndDecode(AgentHistoryResponse.self, from: data, response: response).data
    }

    func getUserAgentHistory(historyId: String) async throws -> (history: AgentHistoryResource, messages: [ThreadMessageResource]) {
        let (data, response) = try await request("/api/user_agent/agent_histories/\(historyId)", auth: .user)
        let detailResponse = try validateAndDecode(AgentHistoryDetailResponse.self, from: data, response: response)
        return (history: detailResponse.data, messages: detailResponse.included?.thread_messages ?? [])
    }

    func deleteUserAgentHistory(historyId: String) async throws {
        let (data, response) = try await request("/api/user_agent/agent_histories/\(historyId)", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
        invalidateRelatedCaches(forResourceType: "agent_history", resourceId: historyId, action: "deleted")
    }

    func getUserAgentCurrentSession() async throws -> (history: AgentHistoryResource, messages: [ThreadMessageResource]) {
        let (data, response) = try await request("/api/user_agent/agent_histories/current", auth: .user)
        let detailResponse = try validateAndDecode(AgentHistoryDetailResponse.self, from: data, response: response)
        return (history: detailResponse.data, messages: detailResponse.included?.thread_messages ?? [])
    }

    func resetUserAgentCurrentSession() async throws {
        let (data, response) = try await request("/api/user_agent/agent_histories/current", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
        invalidateRelatedCaches(forResourceType: "agent_history", resourceId: "current", action: "reset")
    }

    // MARK: - Global Stream

    /// Get URLRequest for global SSE stream (resource lifecycle events)
    func globalStreamURLRequest() throws -> URLRequest {
        return try authorizedStreamRequest(path: "/api/stream/global", auth: .user)
    }

    // MARK: - MCP Integrations
    // API models: MCPServersResponse, MCPServer, MCPServerType, MCPConnectionStatus, MCPConnectionResponse, etc.
    // Defined in: Core/Data/API/Models/MCPServerAPI.swift

    func listMCPServers() async throws -> MCPServersResponse {
        let (data, response) = try await request("/api/mcp/servers", auth: .user)
        return try validateAndDecodeWithDates(MCPServersResponse.self, from: data, response: response)
    }

    func connectMCPServerWithApiKey(serverId: String, apiKey: String) async throws -> MCPConnectionResponse {
        let payload = ["api_key": apiKey]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await request("/api/mcp/servers/\(serverId)/connect", method: "POST", body: body, auth: .user)
        return try validateAndDecode(MCPConnectionResponse.self, from: data, response: response)
    }

    func connectMCPServerWithOAuth(serverId: String, redirectUri: String? = nil) async throws -> MCPConnectionResponse {
        let mobileRedirectUri = redirectUri ?? "heyhouston://oauth-callback"
        let payload = ["redirect_uri": mobileRedirectUri]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await request("/api/mcp/servers/\(serverId)/connect", method: "POST", body: body, auth: .user)
        return try validateAndDecode(MCPConnectionResponse.self, from: data, response: response)
    }

    func disconnectMCPServer(serverId: String) async throws -> Bool {
        let (data, response) = try await request("/api/mcp/servers/\(serverId)/disconnect", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
        return true
    }
    
    // MARK: - Feed
    
    func getCurrentFeed() async throws -> FeedResponse {
        let (data, response) = try await request("/api/feed/current", method: "GET", auth: .user, timeout: 60)
        _ = try validateResponse(data, response)
        return try decodeFeedResponse(from: data)
    }

    func getFeedSchedule() async throws -> FeedSchedule {
        let (data, response) = try await request("/api/feed/schedule", method: "GET", auth: .user)
        return try validateAndDecodeWithDates(FeedSchedule.self, from: data, response: response)
    }

    func triggerFeedInsightGeneration() async throws {
        let (data, response) = try await request("/api/feed/generate_insights", method: "POST", auth: .user)
        _ = try validateResponse(data, response)
    }

    func updateFeedSchedule(period: String, time: String?, enabled: Bool?) async throws -> FeedSchedule {
        var payload: [String: Any] = ["period": period]
        if let time = time { payload["time"] = time }
        if let enabled = enabled { payload["enabled"] = enabled }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await request("/api/feed/schedule", method: "PATCH", body: body, auth: .user)
        return try validateAndDecodeWithDates(FeedSchedule.self, from: data, response: response)
    }

    private func decodeFeedResponse(from data: Data) throws -> FeedResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(FeedResponse.self, from: data)
        } catch {
            APILogger.decodingError(error, context: "FeedResponse", rawResponse: data)
            throw APIError.decodingFailed
        }
    }
    
    func dismissAlert(id: String) async throws {
        let (data, response) = try await request("/api/alerts/\(id)/dismiss", method: "POST", auth: .user)
        _ = try validateResponse(data, response)
    }

    func actOnAlert(id: String) async throws {
        let (data, response) = try await request("/api/alerts/\(id)/act", method: "POST", auth: .user)
        _ = try validateResponse(data, response)
    }

    // MARK: - MCP Generic Auth Methods (New Modular System)
    // API models: MCPAuthInitiateResponse, MCPConnectionInfo, MCPStatusResponse, etc.
    // Defined in: Core/Data/API/Models/MCPServerAPI.swift

    func initiateMCPAuth(serverName: String, redirectUri: String? = nil) async throws -> MCPAuthInitiateResponse {
        var params: [String: Any] = [:]
        if let redirectUri = redirectUri { params["redirect_uri"] = redirectUri }
        let body = try? JSONSerialization.data(withJSONObject: params)
        let (data, response) = try await request("/api/mcp/\(serverName)/auth/initiate", method: "POST", body: body, auth: .user)
        return try validateAndDecode(MCPAuthInitiateResponse.self, from: data, response: response)
    }

    func exchangeMCPToken(serverName: String, credentials: [String: Any], metadata: [String: Any] = [:]) async throws -> MCPConnectionInfo {
        let params: [String: Any] = ["credentials": credentials, "metadata": metadata]
        let body = try JSONSerialization.data(withJSONObject: params)
        let (data, response) = try await request("/api/mcp/\(serverName)/auth/exchange", method: "POST", body: body, auth: .user)
        return try validateAndDecode(MCPConnectionCreateResponse.self, from: data, response: response).connection
    }

    func getMCPConnections(serverName: String) async throws -> [MCPConnectionInfo] {
        let (data, response) = try await request("/api/mcp/\(serverName)/connections", auth: .user)
        return try validateAndDecode(MCPConnectionsListResponse.self, from: data, response: response).connections
    }

    func getMCPStatus(serverName: String) async throws -> MCPStatusResponse {
        let (data, response) = try await request("/api/mcp/\(serverName)/status", auth: .user)
        return try validateAndDecode(MCPStatusResponse.self, from: data, response: response)
    }

    func disconnectMCPConnection(connectionId: Int) async throws {
        let (data, response) = try await request("/api/mcp/connections/\(connectionId)", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
    }

    // MARK: - Custom MCP Server
    // API models: AddServerResponse, CustomServerStatusResponse
    // Defined in: Core/Data/API/Models/MCPServerAPI.swift

    func addCustomServer(name: String, url: String) async throws -> AddServerResponse {
        let body: [String: Any] = ["name": name, "url": url]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await request("/api/mcp/url_servers", method: "POST", body: bodyData, auth: .user)
        // Try to parse error response on failure
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(AddServerResponse.self, from: data) { return errorResponse }
            throw APIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode, message: String(data: data, encoding: .utf8))
        }
        return try validateAndDecode(AddServerResponse.self, from: data, response: response)
    }

    func getCustomServerStatus(serverName: String) async throws -> CustomServerStatusResponse {
        let (data, response) = try await request("/api/mcp/url_servers/\(serverName)", method: "GET", auth: .user)
        return try validateAndDecode(CustomServerStatusResponse.self, from: data, response: response)
    }

    func disconnectCustomServer(serverName: String) async throws {
        let (data, response) = try await request("/api/mcp/url_servers/\(serverName)", method: "DELETE", auth: .user)
        _ = try validateResponse(data, response)
    }
}
