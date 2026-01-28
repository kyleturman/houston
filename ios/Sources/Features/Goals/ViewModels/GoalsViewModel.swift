import Foundation
import SwiftUI
import Observation
import Combine

@MainActor
@Observable
final class GoalsViewModel: BaseViewModel {
    // MARK: - Properties

    var goals: [Goal] = []
    var loading: Bool = false
    var hasLoadedOnce: Bool = false  // Distinguishes "hasn't loaded yet" from "loaded and empty"
    var errorMessage: String?
    var session: SessionManager

    // Publisher for when an optimistic goal is replaced with the real one
    // Emits (tempId, realGoal) so navigation can update selectedItem
    let optimisticGoalReplacedPublisher = PassthroughSubject<(String, Goal), Never>()

    // MARK: - Lifecycle

    init(session: SessionManager) {
        self.session = session
    }

    // MARK: - Public Methods
    // Note: setSession() and makeClient() are provided by BaseViewModel protocol extension

    /// Load goals with Cache-Then-Network pattern
    /// **Swift 6.2 Pattern**: Uses nonisolated async for background work
    func load() async {
        errorMessage = nil
        loading = true

        guard let client = makeClient() else {
            print("❌ GoalsViewModel: Cannot create API client - missing serverURL")
            loading = false
            return
        }

        // Call nonisolated method - compiler runs it on background thread
        await loadDataInBackground(client: client)
        hasLoadedOnce = true
        loading = false
    }

    /// Performs cache-then-network loading on background thread
    /// Swift 6.2: nonisolated async methods automatically run off MainActor
    nonisolated private func loadDataInBackground(client: APIClient) async {
        // ✅ STEP 1: Load from cache first (instant UI) - runs on background thread
        if let cachedData = await client.loadFromCacheOnly(path: "/api/goals", auth: .user) {
            do {
                let resources = try JSONDecoder().decode(JSONAPIList<GoalResource>.self, from: cachedData).data
                let cached = resources.map { Goal.from(resource: $0) }
                await MainActor.run {
                    self.goals = cached
                    self.syncGoalsToAppGroup()
                }
                print("✅ GoalsViewModel: Loaded \(cached.count) goals from cache (instant UI)")
            } catch {
                print("⚠️ GoalsViewModel: Failed to decode cached data - \(error)")
            }
        }

        // ✅ STEP 2: Always fetch fresh from server (even if cache hit)
        do {
            print("🔄 GoalsViewModel: Fetching goals from server...")
            let resources = try await client.listGoals()
            print("✅ GoalsViewModel: Received \(resources.count) goals from server")
            let mapped = resources.map { Goal.from(resource: $0) }
            mapped.forEach { print("   📋 Goal: '\($0.title)' (MCPs: \($0.enabledMcpServers?.count ?? 0))") }
            await MainActor.run {
                self.goals = mapped
                self.syncGoalsToAppGroup()
            }
        } catch {
            // Handle token expiration
            if let apiError = error as? APIClient.APIError,
               case .requestFailed(let statusCode, let message) = apiError,
               statusCode == 401,
               let msg = message, msg.contains("Signature has expired") {
                print("🔄 GoalsViewModel: Token expired, attempting refresh...")

                // Attempt to refresh the token
                let refreshed = await session.refreshUserToken()

                if refreshed {
                    print("✅ GoalsViewModel: Token refreshed, retrying load...")
                    // Retry the load with the new token
                    await self.load()
                    return
                } else {
                    print("❌ GoalsViewModel: Token refresh failed")
                    return
                }
            }

            // If we have cached data, keep it
            await MainActor.run {
                if self.goals.isEmpty {
                    print("❌ GoalsViewModel: Failed to load goals - \(error)")
                    self.errorMessage = "Failed to load goals: \(error.localizedDescription)"
                } else {
                    print("⚠️ GoalsViewModel: Network failed, keeping cached data")
                }
            }
        }
    }

    func create(title: String, description: String?, agentInstructions: String? = nil, learnings: [String]? = nil, enabledMcpServers: [String]? = nil, accentColor: String?) async -> Bool {
        guard let client = makeClient() else { return false }
        do {
            let resource = try await client.createGoal(
                title: title,
                description: description,
                status: nil,
                agentInstructions: agentInstructions,
                learnings: learnings,
                enabledMcpServers: enabledMcpServers,
                accentColor: accentColor
            )
            let g = Goal.from(resource: resource)
            self.goals.insert(g, at: 0)
            return true
        } catch {
            self.errorMessage = "Failed to create goal"
            return false
        }
    }

    func update(goal: Goal) async -> Bool {
        guard let client = makeClient() else { return false }
        do {
            // Status is determined automatically server-side; omit updates to status here
            let resource = try await client.updateGoal(
                id: goal.id,
                title: goal.title,
                description: goal.description,
                status: nil,
                agentInstructions: goal.agentInstructions,
                enabledMcpServers: goal.enabledMcpServers,
                accentColor: goal.accentColor
            )
            let updated = Goal.from(resource: resource)
            if let idx = self.goals.firstIndex(where: { $0.id == goal.id }) {
                self.goals[idx] = updated
            }
            return true
        } catch {
            self.errorMessage = "Failed to update goal"
            return false
        }
    }

    func delete(id: String) async -> Bool {
        guard let client = makeClient() else { return false }
        do {
            try await client.deleteGoal(id: id)
            self.goals.removeAll { $0.id == id }
            return true
        } catch {
            self.errorMessage = "Failed to delete goal"
            return false
        }
    }
    
    func createOptimistically(title: String, description: String?, agentInstructions: String? = nil, learnings: [String]? = nil, enabledMcpServers: [String]? = nil, accentColor: String?) -> Goal {
        // Create optimistic goal with temporary ID
        let tempId = "temp_\(UUID().uuidString)"
        let learningsDict = learnings?.map { ["content": $0] }
        
        let optimisticGoal = Goal(
            id: tempId,
            title: title,
            description: description,
            status: .waiting,
            accentColor: accentColor,
            agentInstructions: agentInstructions,
            enabledMcpServers: enabledMcpServers,
            learnings: learningsDict,
            createdAt: Date(),
            updatedAt: Date(),
            isSyncing: true
        )
        
        // Add to goals list immediately
        self.goals.insert(optimisticGoal, at: 0)
        
        // Save to server in background
        Task {
            guard let client = makeClient() else {
                // Remove optimistic goal if we can't save
                await MainActor.run {
                    self.goals.removeAll { $0.id == tempId }
                    self.errorMessage = "Failed to create goal: No connection"
                }
                return
            }
            
            do {
                let resource = try await client.createGoal(
                    title: title,
                    description: description,
                    status: nil,
                    agentInstructions: agentInstructions,
                    learnings: learnings,
                    enabledMcpServers: enabledMcpServers,
                    accentColor: accentColor
                )
                
                let realGoal = Goal.from(resource: resource)
                
                await MainActor.run {
                    // Replace optimistic goal with real one
                    if let index = self.goals.firstIndex(where: { $0.id == tempId }) {
                        self.goals[index] = realGoal
                        // Notify so navigation can update selectedItem
                        self.optimisticGoalReplacedPublisher.send((tempId, realGoal))
                    }
                }
            } catch {
                await MainActor.run {
                    // Remove optimistic goal on error
                    self.goals.removeAll { $0.id == tempId }
                    self.errorMessage = "Failed to create goal: \(error.localizedDescription)"
                }
            }
        }
        
        return optimisticGoal
    }

    // MARK: - Cache Invalidation & Refresh

    /// Clear goals cache (call before manual refresh or after remote changes)
    func clearCache() {
        guard let client = makeClient() else { return }
        client.clearCacheForPath("/api/goals")
        print("[GoalsViewModel] Cleared goals cache")
    }

    /// Refresh goals from server (for pull-to-refresh UI)
    func refreshFromUI() async {
        clearCache()
        await load()
    }

    // MARK: - App Group Sync for Share Extension

    /// Sync goals to App Group so Share Extension can show goal selection
    private func syncGoalsToAppGroup() {
        guard let appGroup = AppGroupConfig.shared else {
            print("[GoalsViewModel] Warning: Could not access App Group")
            return
        }

        // Encode and save goals directly (Goal is now Codable)
        if let data = try? JSONEncoder().encode(goals) {
            appGroup.set(data, forKey: AppGroupConfig.goalsListKey)
            appGroup.synchronize()
            print("[GoalsViewModel] Synced \(goals.count) goals to App Group")
        } else {
            print("[GoalsViewModel] Failed to encode goals for App Group")
        }
    }
}
