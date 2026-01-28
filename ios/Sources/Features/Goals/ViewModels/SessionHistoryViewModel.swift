import Foundation
import Observation

@MainActor
@Observable
final class SessionHistoryViewModel {
    // MARK: - Observable Properties

    /// List of agent histories (sessions)
    var sessions: [AgentHistory] = []

    /// Current (in-progress) session, if any
    var currentSession: AgentHistory?

    /// Loading state
    var isLoading: Bool = false

    /// Error message
    var errorMessage: String?

    // MARK: - Private Properties

    /// Goal ID (if viewing goal sessions)
    let goalId: String?

    /// Whether viewing user agent sessions
    let isUserAgent: Bool

    /// API client
    private let client: APIClient

    // MARK: - Initialization

    init(goalId: String?, isUserAgent: Bool = false, client: APIClient) {
        self.goalId = goalId
        self.isUserAgent = isUserAgent
        self.client = client
    }

    // MARK: - Public Methods

    /// Load agent histories
    func loadSessions() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let resources: [AgentHistoryResource]

            if isUserAgent {
                resources = try await client.listUserAgentHistories()
            } else if let goalId = goalId {
                resources = try await client.listGoalAgentHistories(goalId: goalId)
            } else {
                throw APIError.invalidContext
            }

            sessions = resources.map { AgentHistory.from(resource: $0) }
        } catch {
            print("❌ [SessionHistoryVM] Failed to load sessions: \(error)")
            errorMessage = "Failed to load session history"
        }
    }

    /// Delete a session
    func deleteSession(_ session: AgentHistory) async {
        do {
            if isUserAgent {
                try await client.deleteUserAgentHistory(historyId: session.id)
            } else if let goalId = goalId {
                try await client.deleteGoalAgentHistory(goalId: goalId, historyId: session.id)
            } else {
                throw APIError.invalidContext
            }

            // Remove from local list (use filter + assignment to trigger observation)
            sessions = sessions.filter { $0.id != session.id }
        } catch {
            print("❌ [SessionHistoryVM] Failed to delete session: \(error)")
            errorMessage = "Failed to delete session"
        }
    }

    /// Handle session deleted from SSE event (other client/device)
    func handleSessionDeleted(historyId: String) {
        sessions = sessions.filter { $0.id != historyId }
    }

    /// Load current (in-progress) session
    func loadCurrentSession() async {
        do {
            let (resource, _) = if isUserAgent {
                try await client.getUserAgentCurrentSession()
            } else if let goalId = goalId {
                try await client.getGoalCurrentSession(goalId: goalId)
            } else {
                throw APIError.invalidContext
            }

            // Only show if there are messages
            if resource.attributes.message_count ?? 0 > 0 {
                currentSession = AgentHistory.from(resource: resource)
            } else {
                currentSession = nil
            }
        } catch {
            // No current session or error - silent fail (current session is optional)
            currentSession = nil
        }
    }

    /// Reset the current session (discard without archiving)
    func resetCurrentSession() async {
        do {
            if isUserAgent {
                try await client.resetUserAgentCurrentSession()
            } else if let goalId = goalId {
                try await client.resetGoalCurrentSession(goalId: goalId)
            } else {
                throw APIError.invalidContext
            }

            currentSession = nil
        } catch {
            print("❌ [SessionHistoryVM] Failed to reset session: \(error)")
            errorMessage = "Failed to reset session"
        }
    }

    /// Handle session reset from SSE event (other client/device)
    func handleSessionReset() {
        currentSession = nil
    }

    // MARK: - Helper Types

    enum APIError: Error {
        case invalidContext
    }
}
