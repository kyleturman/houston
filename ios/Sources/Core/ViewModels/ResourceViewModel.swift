import Foundation
import SwiftUI

/// Protocol for ViewModels that manage lists of resources
/// Extends BaseViewModel to add list-specific functionality
/// Eliminates ~60 lines of boilerplate code per ViewModel
///
/// **Modern iOS 17+ Pattern:**
/// Use `@Observable` macro - no `@Published` annotations needed.
///
/// **Network Awareness:**
/// ViewModels can optionally subscribe to `StateManager.dataRefreshNeededPublisher`
/// to auto-refresh when network is restored. This is done in the view layer:
///
/// ```swift
/// var body: some View {
///     List(viewModel.items) { item in
///         ItemRow(item: item)
///     }
///     .onReceive(stateManager.dataRefreshNeededPublisher) { _ in
///         Task { await viewModel.load() }
///     }
/// }
/// ```
///
/// Usage:
/// ```swift
/// @MainActor
/// @Observable
/// final class GoalNotesViewModel: ResourceViewModel {
///     typealias Resource = Note
///     var items: [Note] = []        // No @Published needed!
///     var loading: Bool = false
///     var errorMessage: String?
///     var session: SessionManager
///
///     init(session: SessionManager, goalId: String) {
///         self.session = session
///         self.goalId = goalId
///     }
///
///     func fetchResources(client: APIClient) async throws -> [Note] {
///         let resources = try await client.listNotes(goalId: goalId)
///         return resources.map { Note.from(resource: $0) }
///     }
/// }
/// ```
///
/// See also:
/// - `BaseViewModel`: Provides common ViewModel functionality (loading, errors, API client)
/// - `StateManager.dataRefreshNeededPublisher`: Triggers refresh on network restoration
@MainActor
protocol ResourceViewModel: BaseViewModel, Sendable {
    /// The type of resource this ViewModel manages (e.g., Note, AgentTaskModel)
    associatedtype Resource: Sendable

    /// The list of resources
    var items: [Resource] { get set }

    /// Fetch resources from the API (called for server requests)
    /// Implement this to call the specific API endpoint for your resource
    /// **Note**: nonisolated to allow calling from background threads
    nonisolated func fetchResources(client: APIClient) async throws -> [Resource]

    /// Load resources from cache only (optional, for cache-then-network pattern)
    /// Implement this to decode cached data and return resources
    /// Default implementation returns empty array (no cache support)
    /// **Note**: nonisolated to allow calling from background threads
    nonisolated func loadFromCache(client: APIClient) async throws -> [Resource]
}

// Default implementations
extension ResourceViewModel {
    /// Default cache loading: returns empty (no cache)
    /// Override in subclasses to enable cache-then-network pattern
    nonisolated func loadFromCache(client: APIClient) async throws -> [Resource] {
        return []
    }

    /// Load resources with Cache-Then-Network pattern
    /// 1. Loads from cache first (instant UI if cache exists)
    /// 2. Always fetches from server (keeps data fresh)
    /// 3. Updates UI smoothly when fresh data arrives
    ///
    /// Handles loading state, error handling, and client creation
    /// Inherited from BaseViewModel: makeClient(), setSession()
    ///
    /// **Swift 6.2 Pattern**: Uses nonisolated async for background work
    /// - No Task.detached (avoids priority loss and Sendable issues)
    /// - Compiler automatically runs nonisolated async on background thread
    /// - Explicit MainActor.run() for UI updates
    func load() async {
        errorMessage = nil
        loading = true

        guard let client = makeClient() else {
            errorMessage = "Failed to create API client"
            loading = false
            return
        }

        // Call nonisolated method - compiler runs it on background thread
        await loadDataInBackground(client: client)
        loading = false
    }

    /// Performs cache-then-network loading on background thread
    /// Swift 6.2: nonisolated async methods automatically run off MainActor
    nonisolated private func loadDataInBackground(client: APIClient) async {
        // ✅ STEP 1: Try cache first (instant, no network delay)
        do {
            let cachedResources = try await loadFromCache(client: client)
            if !cachedResources.isEmpty {
                await MainActor.run {
                    self.items = cachedResources  // Show immediately
                }
                print("[ResourceViewModel] Loaded \(cachedResources.count) items from cache")
            }
        } catch {
            // No cache or error - that's fine, continue to network
        }

        // ✅ STEP 2: Always fetch from server (even if cache hit above)
        do {
            let freshResources = try await fetchResources(client: client)
            await MainActor.run {
                self.items = freshResources  // Update with fresh data
            }
            print("[ResourceViewModel] Loaded \(freshResources.count) items from server")
        } catch {
            // If we already showed cache, keep it
            await MainActor.run {
                if self.items.isEmpty {
                    // Show actual error message for debugging
                    let errorDetails = (error as? APIClient.APIError)?.errorDescription ?? error.localizedDescription
                    self.errorMessage = errorDetails
                    print("[ResourceViewModel] Load error: \(error)")
                } else {
                    print("[ResourceViewModel] Network failed, keeping cached data")
                }
            }
        }
    }
}
