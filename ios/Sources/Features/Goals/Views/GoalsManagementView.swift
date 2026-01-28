import SwiftUI

struct GoalsManagementView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(NavigationViewModel.self) var navigationVM
    @Environment(\.editMode) private var editMode
    @State private var selectedFilter: GoalFilter = .active

    enum GoalFilter: String, CaseIterable {
        case active = "Active"
        case archived = "Archived"

        var statusFilter: Goal.Status? {
            switch self {
            case .active: return nil  // Show all non-archived (active, paused, blocked)
            case .archived: return .archived
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control for active/archived
            Picker("Filter", selection: $selectedFilter) {
                ForEach(GoalFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)

            // Goals list
            if filteredGoals.isEmpty {
                VStack(spacing: 12) {
                    Text(selectedFilter == .active ? "No active goals" : "No archived goals")
                        .font(.headline)
                        .foregroundColor(Color.foreground["000"])

                    if selectedFilter == .active {
                        Text("Create a goal to get started")
                            .font(.body)
                            .foregroundColor(Color.foreground["300"])
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredGoals) { goal in
                        GoalRowView(goal: goal, navigationVM: navigationVM)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if selectedFilter == .archived {
                                    // Unarchive action for archived goals
                                    Button {
                                        Task {
                                            await unarchiveGoal(goal)
                                        }
                                    } label: {
                                        Label("Unarchive", systemImage: "arrow.up.bin")
                                    }
                                    .tint(.blue)
                                }
                            }
                    }
                    .onDelete { indexSet in
                        // Archive goals when deleted in edit mode (active filter only)
                        if selectedFilter == .active {
                            Task {
                                for index in indexSet {
                                    await archiveGoal(filteredGoals[index])
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        // Reorder within filtered view for immediate UI feedback
                        var reorderedFiltered = filteredGoals
                        reorderedFiltered.move(fromOffsets: source, toOffset: destination)

                        // Build complete ordered list
                        let otherGoals = navigationVM.goalsVM.goals.filter { goal in
                            !reorderedFiltered.contains { $0.id == goal.id }
                        }

                        let completeOrder: [Goal]
                        if selectedFilter == .active {
                            // Active goals first (reordered), then archived
                            completeOrder = reorderedFiltered + otherGoals
                        } else {
                            // Active goals first, then archived (reordered)
                            completeOrder = otherGoals + reorderedFiltered
                        }

                        // Update local state immediately
                        navigationVM.goalsVM.goals = completeOrder

                        // Persist to backend asynchronously
                        let orderedIds = completeOrder.map { $0.id }
                        Task {
                            do {
                                guard let client = sessionManager.makeClient() else {
                                    print("Failed to persist goal order: No API client available")
                                    return
                                }
                                try await client.reorderGoals(goalIds: orderedIds)
                            } catch {
                                print("Failed to persist goal order: \(error)")
                                // TODO: Consider showing error to user or reverting local changes
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color.background["000"])
            }
        }
        .background(Color.background["000"])
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if selectedFilter == .active {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .foregroundColor(Color.foreground["000"])
                }
            }
        }
        .refreshable {
            await navigationVM.goalsVM.refreshFromUI()
        }
    }

    /// Filtered goals based on selected filter
    private var filteredGoals: [Goal] {
        let allGoals = navigationVM.goalsVM.goals

        switch selectedFilter {
        case .active:
            // Show all non-archived goals
            return allGoals.filter { $0.status != .archived }
        case .archived:
            // Show only archived goals
            return allGoals.filter { $0.status == .archived }
        }
    }

    /// Archive a goal by updating its status to archived
    private func archiveGoal(_ goal: Goal) async {
        guard let client = sessionManager.makeClient() else {
            print("Failed to archive goal: No API client available")
            return
        }

        do {
            // Update goal status to archived
            let _ = try await client.updateGoal(
                id: goal.id,
                status: "archived"
            )

            // Update local state
            if let index = navigationVM.goalsVM.goals.firstIndex(where: { $0.id == goal.id }) {
                var updatedGoal = goal
                updatedGoal.status = .archived
                navigationVM.goalsVM.goals[index] = updatedGoal

                // If this was the selected goal, deselect it
                if case .goal(let selectedGoal) = navigationVM.selectedItem, selectedGoal.id == goal.id {
                    navigationVM.selectItem(.home)
                }
            }

            // Refresh from server to ensure consistency
            await navigationVM.goalsVM.refreshFromUI()
        } catch {
            print("Failed to archive goal: \(error)")
        }
    }

    /// Unarchive a goal by updating its status to working
    private func unarchiveGoal(_ goal: Goal) async {
        guard let client = sessionManager.makeClient() else {
            print("Failed to unarchive goal: No API client available")
            return
        }

        do {
            // Update goal status to working
            let _ = try await client.updateGoal(
                id: goal.id,
                status: "working"
            )

            // Update local state
            if let index = navigationVM.goalsVM.goals.firstIndex(where: { $0.id == goal.id }) {
                var updatedGoal = goal
                updatedGoal.status = .working
                navigationVM.goalsVM.goals[index] = updatedGoal
            }

            // Refresh from server to ensure consistency
            await navigationVM.goalsVM.refreshFromUI()
        } catch {
            print("Failed to unarchive goal: \(error)")
        }
    }
}

// MARK: - Goal Row View

struct GoalRowView: View {
    let goal: Goal
    let navigationVM: NavigationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: {
            // Navigate back to main view and select this goal
            navigationVM.selectItem(.goal(goal))
            dismiss()
        }) {
            HStack(spacing: 12) {
                // Color indicator
                Rectangle()
                    .fill(Color.accent(goal))
                    .frame(width: 4, height: 40)
                    .cornerRadius(2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title)
                        .font(.headline)
                        .foregroundColor(Color.foreground["000"])

                    if let description = goal.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(Color.foreground["300"])
                            .lineLimit(1)
                    }

                    // Status badge (hide for waiting goals)
                    if goal.status != .waiting {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(for: goal.status))
                                .frame(width: 6, height: 6)

                            Text(goal.status.displayName)
                                .font(.caption)
                                .foregroundColor(Color.foreground["300"])
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color.foreground["300"])
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.background["000"])
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    private func statusColor(for status: Goal.Status) -> Color {
        switch status {
        case .waiting:
            return Color.foreground["300"]
        case .working:
            return .green
        case .archived:
            return Color.foreground["300"]
        }
    }
}

#Preview {
    NavigationStack {
        GoalsManagementView()
    }
}
