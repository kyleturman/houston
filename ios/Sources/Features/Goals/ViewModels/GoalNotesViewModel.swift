import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class GoalNotesViewModel: ResourceViewModel, @unchecked Sendable {
    typealias Resource = Note

    var items: [Note] = []
    var loading: Bool = false
    var errorMessage: String?

    var session: SessionManager
    private let goalId: String

    // Pagination state
    var hasMoreNotes: Bool = true
    var isLoadingMore: Bool = false
    private var nextCursor: String? = nil

    init(session: SessionManager, goalId: String) {
        self.session = session
        self.goalId = goalId
    }

    // Convenience accessor for backward compatibility
    var notes: [Note] {
        get { items }
        set { items = newValue }
    }

    /// Update session reference (called when session changes)
    func setSession(_ session: SessionManager) {
        self.session = session
    }

    // Implement fetchResources for the protocol - now uses pagination
    // Using smaller page size (10) for smoother initial render during swipe animations
    nonisolated func fetchResources(client: APIClient) async throws -> [Note] {
        let (resources, meta) = try await client.listNotesPaginated(goalId: goalId, beforeId: nil, perPage: 10)

        // Update pagination state on main actor
        await MainActor.run {
            self.hasMoreNotes = meta.has_more
            self.nextCursor = meta.next_cursor
        }

        return resources.map { Note.from(resource: $0) }
    }

    // Implement cache loading for cache-then-network pattern
    nonisolated func loadFromCache(client: APIClient) async throws -> [Note] {
        let path = "/api/goals/\(goalId)/notes"
        guard let cachedData = await client.loadFromCacheOnly(path: path, auth: .user) else {
            return []
        }

        // Try to decode with pagination meta first, fall back to simple list
        if let paginatedResponse = try? JSONDecoder().decode(JSONAPICursorPaginatedList<NoteResource>.self, from: cachedData) {
            let hasMore = paginatedResponse.meta.has_more
            let cursor = paginatedResponse.meta.next_cursor
            let notes = paginatedResponse.data.map { Note.from(resource: $0) }
            await MainActor.run {
                self.hasMoreNotes = hasMore
                self.nextCursor = cursor
            }
            return notes
        }

        // Fall back to legacy format without pagination
        let resources = try JSONDecoder().decode(JSONAPIList<NoteResource>.self, from: cachedData).data
        return resources.map { Note.from(resource: $0) }
    }

    /// Load more notes (pagination)
    func loadMore() async {
        guard hasMoreNotes, !isLoadingMore, let cursor = nextCursor else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        guard let client = makeClient() else {
            print("[GoalNotesViewModel] Cannot load more - no client")
            return
        }

        do {
            let (resources, meta) = try await client.listNotesPaginated(goalId: goalId, beforeId: cursor, perPage: 20)
            let newNotes = resources.map { Note.from(resource: $0) }

            // Append to existing items (avoid duplicates)
            let existingIds = Set(items.map { $0.id })
            let uniqueNewNotes = newNotes.filter { !existingIds.contains($0.id) }
            items.append(contentsOf: uniqueNewNotes)

            hasMoreNotes = meta.has_more
            nextCursor = meta.next_cursor

            print("[GoalNotesViewModel] Loaded \(uniqueNewNotes.count) more notes, hasMore: \(hasMoreNotes)")
        } catch {
            print("[GoalNotesViewModel] Failed to load more: \(error)")
        }
    }

    /// Reset pagination state (call before full reload)
    func resetPagination() {
        hasMoreNotes = true
        nextCursor = nil
    }

    // MARK: - Cache Invalidation & Refresh

    /// Clear notes cache for this goal
    func clearCache() {
        guard let client = makeClient() else { return }
        client.clearCacheForPath("/api/goals/\(goalId)/notes")
        client.clearCacheForPath("/api/notes")
        print("[GoalNotesViewModel] Cleared notes cache for goal: \(goalId)")
    }

    /// Refresh notes from server (for pull-to-refresh UI)
    func refreshFromUI() async {
        resetPagination()
        clearCache()
        await load()
    }

    // MARK: - Additional Functionality

    /// Delete a note
    func deleteNote(_ note: Note) async throws {
        guard let client = makeClient() else { throw APIClient.APIError.invalidURL }
        try await client.deleteNote(id: note.id)
    }
}
