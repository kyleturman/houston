import SwiftUI

enum NavigationItem {
    case home
    case goal(Goal)
    case history

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .goal(let goal):
            return goal.title
        case .history:
            return "History"
        }
    }

    var id: String {
        switch self {
        case .home:
            return "home"
        case .goal(let goal):
            return "goal-\(goal.id)"
        case .history:
            return "history"
        }
    }

    /// Unique identifier that changes when content changes
    /// Used for ForEach to detect updates to goal properties
    var uniqueId: String {
        switch self {
        case .home:
            return "home"
        case .goal(let goal):
            return "goal-\(goal.id)-\(goal.title)-\(goal.enabledMcpServers?.count ?? 0)"
        case .history:
            return "history"
        }
    }
    
    @MainActor
    var accentColor: Color? {
        switch self {
        case .home:
            return nil
        case .goal(let goal):
            return Color.accent(goal)
        case .history:
            return nil
        }
    }
}

// MARK: - Hashable & Equatable (content-based, not identity-based)
extension NavigationItem: Hashable, Equatable {
    func hash(into hasher: inout Hasher) {
        // Hash based on uniqueId which includes content that changes
        hasher.combine(uniqueId)
    }

    static func == (lhs: NavigationItem, rhs: NavigationItem) -> Bool {
        // Equality based on uniqueId which includes content that changes
        return lhs.uniqueId == rhs.uniqueId
    }
}

// Navigation destinations for NavigationPath
enum NavigationDestination: Hashable {
    case history
    case notes
    case goalsManagement
}
