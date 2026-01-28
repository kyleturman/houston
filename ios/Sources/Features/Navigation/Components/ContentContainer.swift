import SwiftUI

/// Main content area container that switches between different navigation states.
/// Displays goals list or selected goal detail view based on navigation.
struct ContentContainer: View {
    @Bindable var navigationVM: NavigationViewModel
    @Environment(SessionManager.self) var session
    let noteTransition: Namespace.ID

    var body: some View {
        TabView(selection: $navigationVM.selectedItem) {
            ForEach(navigationVM.navigationItems, id: \.uniqueId) { item in
                Group {
                    switch item {
                    case .home:
                        HomeView(noteTransition: noteTransition)
                            .environment(navigationVM)
                    case .goal(let goal):
                        // Direct GoalView - data is prefetched via GoalDataPool
                        GoalView(goal: goal)
                            .environment(session)
                            .environment(navigationVM)
                            .id(item.uniqueId)
                    case .history:
                        // History should not appear in TabView, handled by NavigationStack
                        EmptyView()
                    }
                }
                .tag(item)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: navigationVM.selectedItem) { _, _ in
            // Prefetch adjacent goals for smooth swiping
            navigationVM.prefetchAdjacentGoals(session: session)
        }
    }
}
