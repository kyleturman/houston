import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class ActivityViewModel: BaseViewModel, @unchecked Sendable {
    var activities: [AgentActivityItem] = []
    var loading: Bool = false
    var errorMessage: String?
    var session: SessionManager

    // Pagination state
    var currentPage: Int = 1
    var hasMorePages: Bool = false
    var loadingMore: Bool = false

    // Filters
    var selectedAgentType: String? = nil
    var selectedGoalId: String? = nil

    private let perPage: Int = 20

    init(session: SessionManager) {
        self.session = session
    }

    /// Update session reference (called when session changes)
    func setSession(_ session: SessionManager) {
        self.session = session
    }

    /// Load first page of activities
    func load() async {
        errorMessage = nil
        loading = true
        currentPage = 1
        hasMorePages = false

        guard let client = makeClient() else {
            errorMessage = "Failed to create API client"
            loading = false
            return
        }

        await loadDataInBackground(client: client, page: 1, append: false)
        loading = false
    }

    /// Load next page (for infinite scroll)
    func loadMore() async {
        guard !loadingMore && hasMorePages else { return }

        loadingMore = true
        let nextPage = currentPage + 1

        guard let client = makeClient() else {
            loadingMore = false
            return
        }

        await loadDataInBackground(client: client, page: nextPage, append: true)
        loadingMore = false
    }

    /// Refresh from server (for pull-to-refresh)
    func refresh() async {
        await load()
    }

    /// Apply filter and reload
    func filterByAgentType(_ agentType: String?) async {
        selectedAgentType = agentType
        await load()
    }

    /// Apply goal filter and reload
    func filterByGoal(_ goalId: String?) async {
        selectedGoalId = goalId
        await load()
    }

    // MARK: - Private

    /// Load data from API on background thread
    nonisolated private func loadDataInBackground(client: APIClient, page: Int, append: Bool) async {
        do {
            let (resources, meta) = try await client.listAgentActivities(
                page: page,
                perPage: perPage,
                agentType: selectedAgentType,
                goalId: selectedGoalId
            )

            let newActivities = resources.map { AgentActivityItem.from(resource: $0) }

            await MainActor.run {
                if append {
                    // Append to existing list
                    self.activities.append(contentsOf: newActivities)
                } else {
                    // Replace list
                    self.activities = newActivities
                }

                self.currentPage = meta.current_page
                self.hasMorePages = meta.has_next_page

                print("[ActivityViewModel] Loaded \(newActivities.count) activities (page \(meta.current_page)/\(meta.total_pages))")
            }
        } catch {
            await MainActor.run {
                if !append && self.activities.isEmpty {
                    self.errorMessage = "Failed to load activities"
                }
                print("[ActivityViewModel] Load error: \(error)")
            }
        }
    }
}
