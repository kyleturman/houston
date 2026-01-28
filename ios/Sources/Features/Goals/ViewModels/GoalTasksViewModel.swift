import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class GoalTasksViewModel: ResourceViewModel, @unchecked Sendable {
    typealias Resource = AgentTaskModel

    var items: [AgentTaskModel] = []
    var loading: Bool = false
    var errorMessage: String?

    var session: SessionManager
    private let goalId: String

    init(session: SessionManager, goalId: String) {
        self.session = session
        self.goalId = goalId
    }

    // Convenience accessor for backward compatibility
    var tasks: [AgentTaskModel] {
        get { items }
        set { items = newValue }
    }

    /// Update session reference (called when session changes)
    func setSession(_ session: SessionManager) {
        self.session = session
    }

    // Implement fetchResources for the protocol
    nonisolated func fetchResources(client: APIClient) async throws -> [AgentTaskModel] {
        let resources = try await client.listGoalTasks(goalId: goalId)
        return resources.map { AgentTaskModel.from(resource: $0) }
    }

    // Implement cache loading for cache-then-network pattern
    nonisolated func loadFromCache(client: APIClient) async throws -> [AgentTaskModel] {
        let path = "/api/goals/\(goalId)/agent_tasks"
        guard let cachedData = await client.loadFromCacheOnly(path: path, auth: .user) else {
            return []
        }

        let resources = try JSONDecoder().decode(JSONAPIList<AgentTaskResource>.self, from: cachedData).data
        return resources.map { AgentTaskModel.from(resource: $0) }
    }

    // MARK: - Cache Invalidation & Refresh

    /// Clear tasks cache for this goal
    func clearCache() {
        guard let client = makeClient() else { return }
        client.clearCacheForPath("/api/goals/\(goalId)/agent_tasks")
        print("[GoalTasksViewModel] Cleared tasks cache for goal: \(goalId)")
    }

    /// Refresh tasks from server (for pull-to-refresh UI)
    func refreshFromUI() async {
        clearCache()
        await load()
    }
}
