import Foundation

/// Pool for caching ChatViewModels by context to avoid recreating them on navigation.
///
/// Benefits:
/// - Preserves message state when switching between goals
/// - Prevents SSE connection churn (new connection per goal switch)
/// - Enables preloading without starting SSE streams
///
/// Usage:
/// ```swift
/// let vm = pool.get(context: .goal(id: goalId), session: session, goal: goal)
/// vm.startStream()  // Only when chat sheet opens
/// ```
@MainActor
final class ChatViewModelPool {

    /// Shared instance for app-wide use
    static let shared = ChatViewModelPool()

    /// Cache of ViewModels keyed by context identifier
    private var cache: [String: ChatViewModel] = [:]

    /// Maximum number of ViewModels to keep in cache
    private let maxCacheSize = 10

    private init() {}

    /// Get or create a ChatViewModel for the given context.
    ///
    /// - Parameters:
    ///   - context: The agent chat context (goal ID or user agent)
    ///   - session: Session manager for API calls
    ///   - goal: Optional goal for goal-specific chats
    ///   - preloadOnly: If true, don't start SSE stream (just load messages)
    /// - Returns: Cached or newly created ChatViewModel
    func get(
        context: AgentChatDataSource.Context,
        session: SessionManager,
        goal: Goal? = nil,
        preloadOnly: Bool = false
    ) -> ChatViewModel {
        let key = cacheKey(for: context)

        // Return cached ViewModel if available
        if let cached = cache[key] {
            print("[ChatViewModelPool] Cache hit for \(key)")
            return cached
        }

        print("[ChatViewModelPool] Cache miss for \(key), creating new ViewModel")

        // Create new ViewModel
        let viewModel = ChatViewModel(session: session, context: context, goal: goal)

        // Enforce cache size limit (LRU-ish: remove oldest entries)
        if cache.count >= maxCacheSize {
            // Remove the first (oldest) entry
            if let oldestKey = cache.keys.first {
                print("[ChatViewModelPool] Evicting \(oldestKey) to make room")
                cache[oldestKey]?.stopStream()
                cache.removeValue(forKey: oldestKey)
            }
        }

        cache[key] = viewModel
        return viewModel
    }

    /// Preload a ChatViewModel without starting SSE stream.
    ///
    /// Call this when switching goals to have messages ready,
    /// but only start the stream when the chat sheet opens.
    func preload(
        context: AgentChatDataSource.Context,
        session: SessionManager,
        goal: Goal? = nil
    ) async {
        let viewModel = get(context: context, session: session, goal: goal, preloadOnly: true)

        // Initialize loads messages but we control when SSE starts
        await viewModel.initializeWithoutStream()
    }

    /// Remove a specific context from the cache.
    func invalidate(context: AgentChatDataSource.Context) {
        let key = cacheKey(for: context)
        if let vm = cache[key] {
            vm.stopStream()
            cache.removeValue(forKey: key)
            print("[ChatViewModelPool] Invalidated \(key)")
        }
    }

    /// Clear all cached ViewModels (e.g., on logout).
    func clear() {
        for (_, vm) in cache {
            vm.stopStream()
        }
        cache.removeAll()
        print("[ChatViewModelPool] Cleared all cached ViewModels")
    }

    /// Stop all active SSE streams (e.g., when app backgrounds).
    func stopAllStreams() {
        for (key, vm) in cache {
            vm.stopStream()
            print("[ChatViewModelPool] Stopped stream for \(key)")
        }
    }

    /// Generate cache key from context.
    private func cacheKey(for context: AgentChatDataSource.Context) -> String {
        switch context {
        case .goal(let id):
            return "goal:\(id)"
        case .task(let id):
            return "task:\(id)"
        case .userAgent:
            return "userAgent"
        }
    }
}
