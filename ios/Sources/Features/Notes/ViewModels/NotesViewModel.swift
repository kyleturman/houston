import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class NotesViewModel: ResourceViewModel, @unchecked Sendable {
    typealias Resource = Note

    var items: [Note] = []
    var loading: Bool = false
    var errorMessage: String?
    var session: SessionManager

    // Filtering and search
    var searchText: String = ""
    var selectedSource: NoteSourceFilter = .all

    enum NoteSourceFilter: String, CaseIterable {
        case all = "All"
        case user = "User"
        case agent = "Agent"

        var sourceValue: Note.Source? {
            switch self {
            case .all: return nil
            case .user: return .user
            case .agent: return .agent
            }
        }
    }

    init(session: SessionManager) {
        self.session = session
    }

    /// Update session reference (called when session changes)
    func setSession(_ session: SessionManager) {
        self.session = session
    }

    // Implement fetchResources for the protocol
    nonisolated func fetchResources(client: APIClient) async throws -> [Note] {
        let resources = try await client.listAllNotes()
        // Backend returns notes in descending order (most recent first)
        return resources.map { Note.from(resource: $0) }
    }

    /// Filtered notes based on search and source filter
    var filteredNotes: [Note] {
        var filtered = items

        // Apply source filter
        if let sourceFilter = selectedSource.sourceValue {
            filtered = filtered.filter { $0.source == sourceFilter }
        }

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { note in
                let searchLower = searchText.lowercased()
                let titleMatch = note.title?.lowercased().contains(searchLower) ?? false
                let contentMatch = note.content?.lowercased().contains(searchLower) ?? false
                return titleMatch || contentMatch
            }
        }

        return filtered
    }

    /// Clear notes cache
    func clearCache() {
        guard let client = makeClient() else { return }
        client.clearCacheForPath("/api/notes")
        print("[NotesViewModel] Cleared notes cache")
    }

    /// Refresh notes from server (for pull-to-refresh UI)
    func refreshFromUI() async {
        clearCache()
        await load()
    }

    /// Delete a note
    func deleteNote(_ note: Note) async throws {
        guard let client = makeClient() else { throw APIClient.APIError.invalidURL }
        try await client.deleteNote(id: note.id)

        // Remove from local list immediately for instant UI update
        items.removeAll { $0.id == note.id }
    }

    /// Update search text and trigger filtering
    func updateSearch(_ text: String) {
        searchText = text
    }

    /// Update source filter
    func updateSourceFilter(_ filter: NoteSourceFilter) {
        selectedSource = filter
    }
}
