import SwiftUI
import Observation

@MainActor
@Observable
class NavigationViewModel {
    var selectedItem: NavigationItem = .home
    var showingSideMenu = false
    var showingGoalChat = false
    var showingHomeChat = false
    var showingGoalCreation = false

    // Unified sheet management
    enum SheetType: Identifiable, Equatable {
        case note(String)
        case task(String)
        case goalCreation

        var id: String {
            switch self {
            case .note(let id): return "note-\(id)"
            case .task(let id): return "task-\(id)"
            case .goalCreation: return "goal-creation"
            }
        }
    }

    var activeSheet: SheetType?

    // Shared content from Share Extension
    var sharedURL: String?
    var sharedText: String?

    // Navigation path for true depth detection
    var navigationPath = NavigationPath()

    // Store the previous item before navigating to History
    private var previousItemBeforeHistory: NavigationItem?

    // Track navigation depth for footer visibility - TRUE DEPTH DETECTION
    var isInDeepNavigation: Bool {
        navigationPath.count > 0
    }

    // Note composition state - allows opening note sheet with specific goal
    var showingNoteCompose = false
    var goalForNoteCompose: Goal?
    var noteComposeSourceID: String = "noteCompose" // Tracks which button opened the sheet for zoom animation

    private let goalsViewModel: GoalsViewModel

    // Cached navigation items - only rebuilt when goals change
    private var _cachedNavigationItems: [NavigationItem] = [.home]
    private var _cachedGoalIds: [String] = []

    // Public accessor for GoalsViewModel
    var goalsVM: GoalsViewModel {
        goalsViewModel
    }

    init(goalsViewModel: GoalsViewModel) {
        self.goalsViewModel = goalsViewModel
        rebuildNavigationItems()
    }

    /// Call this when goals are added, removed, or reordered
    func rebuildNavigationItems() {
        let goalIds = goalsViewModel.goals.map { $0.id }
        guard goalIds != _cachedGoalIds else { return }

        _cachedGoalIds = goalIds
        _cachedNavigationItems = [.home] + goalsViewModel.goals.map { .goal($0) }
    }

    /// Updates selectedItem if it references a goal that was updated
    /// Call this after goalsViewModel.goals is refreshed
    func syncSelectedItem() {
        // Rebuild navigation items if goals changed
        rebuildNavigationItems()

        // If current selection is a goal, find the updated version in goalsViewModel
        if case .goal(let currentGoal) = selectedItem {
            if let updatedGoal = goalsViewModel.goals.first(where: { $0.id == currentGoal.id }) {
                // Update to the fresh Goal object
                selectedItem = .goal(updatedGoal)
            }
        }
    }

    var navigationItems: [NavigationItem] {
        // Auto-rebuild if goals changed (handles cache-then-network pattern)
        let currentGoalIds = goalsViewModel.goals.map { $0.id }
        if currentGoalIds != _cachedGoalIds {
            rebuildNavigationItems()
        }
        return _cachedNavigationItems
    }

    /// Prefetch data for adjacent goals when selection changes.
    ///
    /// Call this after selectedItem changes to warm the cache for smooth swiping.
    /// Prefetches the goal to the left and right of the current selection.
    func prefetchAdjacentGoals(session: SessionManager) {
        let items = navigationItems
        guard let currentIndex = items.firstIndex(of: selectedItem) else { return }

        // Prefetch previous item (if exists and is a goal)
        if currentIndex > 0 {
            if case .goal(let prevGoal) = items[currentIndex - 1] {
                Task {
                    await GoalDataPool.shared.prefetch(goalId: prevGoal.id, session: session)
                }
            }
        }

        // Prefetch next item (if exists and is a goal)
        if currentIndex < items.count - 1 {
            if case .goal(let nextGoal) = items[currentIndex + 1] {
                Task {
                    await GoalDataPool.shared.prefetch(goalId: nextGoal.id, session: session)
                }
            }
        }
    }

    func selectItem(_ item: NavigationItem) {
        selectedItem = item
    }
    
    func toggleSideMenu() {
        // Add haptic feedback for better UX
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showingSideMenu.toggle()
        }
    }
    
    func closeSideMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showingSideMenu = false
        }
    }
    
    func openGoalChat() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showingGoalChat = true
        }
    }
    
    func closeGoalChat() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showingGoalChat = false
        }
    }
    
    func openHomeChat() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showingHomeChat = true
        }
    }
    
    func closeHomeChat() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showingHomeChat = false
        }
    }
    
    func openGoalCreation() {
        activeSheet = .goalCreation
        showingGoalCreation = true
    }

    func openNote(id: String) {
        activeSheet = .note(id)
    }

    func openTask(id: String) {
        activeSheet = .task(id)
    }

    func openNoteCompose(goal: Goal?, sourceID: String = "noteCompose") {
        print("📝 [NavigationVM] openNoteCompose called with goal: \(goal?.title ?? "nil"), sourceID: \(sourceID)")
        goalForNoteCompose = goal
        noteComposeSourceID = sourceID
        print("📝 [NavigationVM] goalForNoteCompose set to: \(goalForNoteCompose?.title ?? "nil")")
        showingNoteCompose = true
    }

    func closeSheet() {
        activeSheet = nil
    }

    func closeGoalCreation() {
        showingGoalCreation = false
    }

    func setSharedContent(url: String?, text: String?) {
        sharedURL = url
        sharedText = text
    }

    func clearSharedContent() {
        sharedURL = nil
        sharedText = nil
    }

    func navigateToHistory() {
        closeSideMenu()
        // Store current item before navigating to History
        if selectedItem != .history {
            previousItemBeforeHistory = selectedItem
        }
        // Use NavigationPath instead of changing selectedItem
        navigationPath.append(NavigationDestination.history)
    }

    func navigateToNotes() {
        closeSideMenu()
        navigationPath.append(NavigationDestination.notes)
    }

    func navigateToGoals() {
        closeSideMenu()
        navigationPath.append(NavigationDestination.goalsManagement)
    }

    func navigateBackFromHistory() {
        // Pop the navigation path to go back
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
        // Restore previous item if available
        if let previousItem = previousItemBeforeHistory {
            selectItem(previousItem)
            previousItemBeforeHistory = nil
        }
    }
}
