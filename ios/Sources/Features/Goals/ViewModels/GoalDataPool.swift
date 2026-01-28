import Foundation

/// Pool for caching goal data (notes/tasks ViewModels) to enable prefetching and smooth swiping.
///
/// Benefits:
/// - Preserves data state when swiping between goals
/// - Enables prefetching of adjacent goals for instant loading
/// - Prevents redundant API calls when navigating back to a goal
///
/// Usage:
/// ```swift
/// let (notesVM, tasksVM) = GoalDataPool.shared.get(goalId: goal.id, session: session)
/// // ViewModels are already loaded if prefetched, or will load on access
/// ```
@MainActor
final class GoalDataPool {

    /// Shared instance for app-wide use
    static let shared = GoalDataPool()

    /// Cache of notes ViewModels keyed by goal ID
    private var notesCache: [String: GoalNotesViewModel] = [:]

    /// Cache of tasks ViewModels keyed by goal ID
    private var tasksCache: [String: GoalTasksViewModel] = [:]

    /// Track goals currently being prefetched to avoid duplicate requests
    private var prefetchingGoals: Set<String> = []

    /// Track cache access order for LRU eviction
    private var accessOrder: [String] = []

    /// Maximum number of goals to keep in cache
    private let maxCacheSize = 10

    private init() {}

    /// Get or create ViewModels for a goal.
    ///
    /// - Parameters:
    ///   - goalId: The goal's ID
    ///   - session: Session manager for API calls
    /// - Returns: Tuple of (notes ViewModel, tasks ViewModel)
    func get(goalId: String, session: SessionManager) -> (notes: GoalNotesViewModel, tasks: GoalTasksViewModel) {
        // Update access order for LRU
        updateAccessOrder(goalId)

        // Get or create notes VM
        let notesVM: GoalNotesViewModel
        if let cached = notesCache[goalId] {
            cached.setSession(session)
            notesVM = cached
            print("[GoalDataPool] Notes cache hit for goal: \(goalId)")
        } else {
            notesVM = GoalNotesViewModel(session: session, goalId: goalId)
            enforceCacheLimit()
            notesCache[goalId] = notesVM
            print("[GoalDataPool] Notes cache miss for goal: \(goalId), created new VM")
        }

        // Get or create tasks VM
        let tasksVM: GoalTasksViewModel
        if let cached = tasksCache[goalId] {
            cached.setSession(session)
            tasksVM = cached
        } else {
            tasksVM = GoalTasksViewModel(session: session, goalId: goalId)
            tasksCache[goalId] = tasksVM
        }

        return (notesVM, tasksVM)
    }

    /// Check if a goal's data is already cached.
    func isCached(goalId: String) -> Bool {
        return notesCache[goalId] != nil
    }

    /// Prefetch data for a goal in background.
    ///
    /// Does nothing if already cached or currently prefetching.
    /// Call this for adjacent goals when user lands on a goal.
    ///
    /// - Parameters:
    ///   - goalId: The goal's ID to prefetch
    ///   - session: Session manager for API calls
    func prefetch(goalId: String, session: SessionManager) async {
        // Skip if already cached or in-flight
        guard notesCache[goalId] == nil, !prefetchingGoals.contains(goalId) else {
            print("[GoalDataPool] Skipping prefetch for goal: \(goalId) (cached: \(notesCache[goalId] != nil), prefetching: \(prefetchingGoals.contains(goalId)))")
            return
        }

        prefetchingGoals.insert(goalId)
        defer { prefetchingGoals.remove(goalId) }

        print("[GoalDataPool] Prefetching goal: \(goalId)")

        let (notesVM, tasksVM) = get(goalId: goalId, session: session)

        // Load both in parallel using async let
        async let notesLoad: () = notesVM.load()
        async let tasksLoad: () = tasksVM.load()
        _ = await (notesLoad, tasksLoad)

        print("[GoalDataPool] Prefetch complete for goal: \(goalId) - notes: \(notesVM.notes.count), tasks: \(tasksVM.tasks.count)")
    }

    /// Clear cache for a specific goal.
    ///
    /// Call this when goal is deleted or data needs to be fully refreshed.
    func evict(goalId: String) {
        notesCache.removeValue(forKey: goalId)
        tasksCache.removeValue(forKey: goalId)
        accessOrder.removeAll { $0 == goalId }
        print("[GoalDataPool] Evicted goal: \(goalId)")
    }

    /// Clear all cached data.
    ///
    /// Call this on logout or when user changes.
    func clear() {
        notesCache.removeAll()
        tasksCache.removeAll()
        prefetchingGoals.removeAll()
        accessOrder.removeAll()
        print("[GoalDataPool] Cleared all cached ViewModels")
    }

    /// Invalidate and reload data for a goal.
    ///
    /// Call this when StateManager reports changes for a goal.
    func invalidateAndReload(goalId: String, session: SessionManager) async {
        guard let notesVM = notesCache[goalId], let tasksVM = tasksCache[goalId] else {
            return
        }

        print("[GoalDataPool] Invalidating and reloading goal: \(goalId)")

        // Reload both in parallel
        async let notesLoad: () = notesVM.load()
        async let tasksLoad: () = tasksVM.load()
        _ = await (notesLoad, tasksLoad)
    }

    // MARK: - Private Helpers

    /// Update LRU access order
    private func updateAccessOrder(_ goalId: String) {
        accessOrder.removeAll { $0 == goalId }
        accessOrder.append(goalId)
    }

    /// Enforce LRU cache limit by evicting oldest entries
    private func enforceCacheLimit() {
        while notesCache.count >= maxCacheSize, let oldestKey = accessOrder.first {
            notesCache.removeValue(forKey: oldestKey)
            tasksCache.removeValue(forKey: oldestKey)
            accessOrder.removeFirst()
            print("[GoalDataPool] LRU evicted goal: \(oldestKey)")
        }
    }
}
