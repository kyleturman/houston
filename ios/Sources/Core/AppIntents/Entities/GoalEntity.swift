import AppIntents
import Foundation

/// Goal entity for App Intents
/// Used for goal selection in Siri, Shortcuts, and other system surfaces
struct GoalEntity: AppEntity, Identifiable {
    let id: String
    let title: String
    let accentColor: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Goal")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            image: .init(systemName: "target")
        )
    }

    static let defaultQuery = GoalEntityQuery()
}

/// Query for loading goals from backend
struct GoalEntityQuery: EnumerableEntityQuery {
    /// Load all active goals from API
    func allEntities() async throws -> [GoalEntity] {
        let client = try IntentAPIClient.create()
        let goals = try await client.listGoals()

        // Only return active goals (exclude archived)
        return goals
            .filter { $0.attributes.status != "archived" }
            .map { resource in
                GoalEntity(
                    id: resource.id,
                    title: resource.attributes.title,
                    accentColor: resource.attributes.accent_color
                )
            }
    }

    /// Load specific goals by ID
    func entities(for identifiers: [String]) async throws -> [GoalEntity] {
        let all = try await allEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    /// Suggested entities for parameter prompts
    func suggestedEntities() async throws -> [GoalEntity] {
        // Return all active goals (small list suitable for suggestion)
        return try await allEntities()
    }
}
