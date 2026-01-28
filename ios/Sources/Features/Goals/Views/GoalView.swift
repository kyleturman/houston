import SwiftUI

struct GoalView: View {
    @Environment(SessionManager.self) var session
    @Environment(StateManager.self) var stateManager
    @State private var goal: Goal
    @State private var notesVM: GoalNotesViewModel
    @State private var tasksVM: GoalTasksViewModel
    @Environment(NavigationViewModel.self) var navigationVM
    @State private var showingAddNote: Bool = false
    @State private var noteToEdit: Note? = nil
    @State private var showingTaskChat: Bool = false
    @State private var selectedTaskId: String? = nil
    @State private var showingGoalSettings: Bool = false
    @State private var showingOptionsMenu: Bool = false
    @State private var showingArchiveConfirmation: Bool = false
    @State private var showingLearnings: Bool = false
    @State private var frequency: [String] = ["morning", "evening"] // TODO: Move to model

    // Note error recovery state
    @State private var noteToRecover: Note? = nil
    @State private var recoveryErrorMessage: String? = nil

    // Task state to prevent cancellation during swipes and events
    @State private var notesLoadTask: Task<Void, Never>? = nil
    @State private var tasksLoadTask: Task<Void, Never>? = nil
    @State private var notesReloadTask: Task<Void, Never>? = nil
    @State private var tasksReloadTask: Task<Void, Never>? = nil

    // Timer for live check-in time updates (refreshes every minute)
    @State private var timeRefreshTimer: Timer? = nil
    @State private var timeRefreshTrigger: Bool = false

    init(goal: Goal) {
        _goal = State(initialValue: goal)
        // Use skipLoad: true for placeholder sessions - real session set via Environment
        _notesVM = State(wrappedValue: GoalNotesViewModel(session: SessionManager(skipLoad: true), goalId: goal.id))
        _tasksVM = State(wrappedValue: GoalTasksViewModel(session: SessionManager(skipLoad: true), goalId: goal.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Show syncing indicator if goal is being saved
                if goal.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Saving goal...")
                            .font(.footnote)
                            .foregroundColor(Color.foreground["300"])
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.background["100"])
                    .cornerRadius(8)
                }

                header
                agentHelpBanner
                timeline
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .refreshable {
            // Pull-to-refresh: reload notes and tasks from server
            async let notesRefresh: () = notesVM.refreshFromUI()
            async let tasksRefresh: () = tasksVM.refreshFromUI()
            _ = await (notesRefresh, tasksRefresh)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.3), value: true)
        .onAppear {
            // Start timer for live check-in time updates (every 30 seconds)
            timeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                Task { @MainActor in
                    timeRefreshTrigger.toggle()
                }
            }

            // Skip loading for optimistic goals (they don't exist on server yet)
            // View will be recreated with real ID when goal is saved
            guard !goal.isSyncing else {
                print("[GoalView] Skipping load for syncing goal - view will refresh when save completes")
                return
            }

            // Get ViewModels from pool (may already be prefetched)
            let (poolNotes, poolTasks) = GoalDataPool.shared.get(goalId: goal.id, session: session)
            notesVM = poolNotes
            tasksVM = poolTasks

            // Load if not already loaded (no-op if data was prefetched)
            notesLoadTask = Task {
                await notesVM.load()
            }
            tasksLoadTask = Task {
                await tasksVM.load()
            }
        }
        .onDisappear {
            // Stop the timer when view disappears
            timeRefreshTimer?.invalidate()
            timeRefreshTimer = nil
        }
        .onChange(of: goal.id) { _, newGoalId in
            // Cancel previous loads
            notesLoadTask?.cancel()
            tasksLoadTask?.cancel()

            // Get ViewModels from pool (should be prefetched by ContentContainer)
            let (poolNotes, poolTasks) = GoalDataPool.shared.get(goalId: newGoalId, session: session)
            notesVM = poolNotes
            tasksVM = poolTasks

            // Load if not already loaded - NO DELAY since data should be prefetched
            notesLoadTask = Task {
                guard !Task.isCancelled else { return }
                await notesVM.load()
            }
            tasksLoadTask = Task {
                guard !Task.isCancelled else { return }
                await tasksVM.load()
            }
        }
        .sheet(isPresented: $showingAddNote) {
            NoteComposeSheetView(
                initialGoal: goal,
                existingNote: noteToRecover,
                isRecoveryMode: noteToRecover != nil,
                initialErrorMessage: recoveryErrorMessage,
                onCreated: { newNote in
                    // Note created - clear recovery state (StateManager will auto-refresh)
                    noteToRecover = nil
                    recoveryErrorMessage = nil
                },
                onCreateFailed: { failedNote, errorMessage in
                    // Save failed - set up for recovery
                    noteToRecover = failedNote
                    recoveryErrorMessage = errorMessage
                    // Re-open sheet after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingAddNote = true
                    }
                }
            )
            .environment(session)
            .environment(navigationVM)
        }
        .sheet(item: $noteToEdit) { note in
            NoteComposeSheetView(initialGoal: goal, existingNote: note)
            .environment(session)
            .environment(navigationVM)
        }
        .sheet(isPresented: $showingTaskChat) {
            if let tid = selectedTaskId {
                TaskChatSheetView(taskId: tid)
                    .environment(session)
                    .environment(navigationVM)
            }
        }
        .sheet(isPresented: $showingGoalSettings) {
            GoalSettingsSheet(goal: goal)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingOptionsMenu) {
            MenuSheet(items: [
                MenuItem(icon: "long.text.page.and.pencil", title: "Edit goal") {
                    showingGoalSettings = true
                },
                MenuItem(icon: "lightbulb", title: "Learnings") {
                    showingLearnings = true
                },
                MenuItem(icon: "trash", title: "Archive goal", isDestructive: true) {
                    showingArchiveConfirmation = true
                }
            ])
            .presentationDetents([.height(MenuSheet.height(for: 3))])
            .presentationDragIndicator(.visible)
            .presentationBackground(.thinMaterial)
        }
        .sheet(isPresented: $showingLearnings) {
            LearningsView(goal: goal)
        }
        .alert("Archive Goal", isPresented: $showingArchiveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Archive", role: .destructive) {
                archiveGoal()
            }
        } message: {
            Text("Are you sure you want to archive this goal?")
        }
        // MARK: - Real-time Updates via StateManager (with debouncing to prevent reload storms)
        // Note: All handlers skip for syncing goals (temp IDs) since they don't exist on server yet.
        // View will be recreated with real ID when goal is saved.
        .onReceive(stateManager.noteCreatedPublisher) { event in
            guard !goal.isSyncing, event.goal_id == Int(goal.id) else { return }
            notesReloadTask?.cancel()
            notesReloadTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await notesVM.load()
            }
        }
        .onReceive(stateManager.noteUpdatedPublisher) { event in
            guard !goal.isSyncing, event.goal_id == Int(goal.id) else { return }
            notesReloadTask?.cancel()
            notesReloadTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await notesVM.load()
            }
        }
        .onReceive(stateManager.noteDeletedPublisher) { event in
            guard !goal.isSyncing, event.goal_id == Int(goal.id) else { return }
            notesReloadTask?.cancel()
            notesReloadTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await notesVM.load()
            }
        }
        .onReceive(stateManager.taskCreatedPublisher) { event in
            guard !goal.isSyncing, event.goal_id == Int(goal.id) else { return }
            tasksReloadTask?.cancel()
            tasksReloadTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await tasksVM.load()
            }
        }
        .onReceive(stateManager.taskUpdatedPublisher) { event in
            guard !goal.isSyncing, event.goal_id == Int(goal.id) else { return }
            tasksReloadTask?.cancel()
            tasksReloadTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await tasksVM.load()
            }
        }
        .onReceive(stateManager.taskCompletedPublisher) { event in
            guard !goal.isSyncing, event.goal_id == Int(goal.id) else { return }
            tasksReloadTask?.cancel()
            tasksReloadTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await tasksVM.load()
            }
        }
        .onReceive(stateManager.goalUpdatedPublisher) { event in
            guard !goal.isSyncing, event.goal_id == Int(goal.id) else { return }

            // Immediately update check-in from SSE data for instant UI feedback
            if let checkInData = event.next_check_in {
                // Update the goal's runtime state with new check-in info
                var updatedGoal = goal
                var newRuntimeState = goal.runtimeState ?? [:]
                var checkIns = newRuntimeState["check_ins"] as? [String: Any] ?? [:]
                checkIns[checkInData.slot] = [
                    "scheduled_for": checkInData.scheduled_for,
                    "intent": checkInData.intent
                ]
                newRuntimeState["check_ins"] = checkIns
                updatedGoal.runtimeState = newRuntimeState
                self.goal = updatedGoal
            } else {
                // No check-in in event - might have been cleared
                var updatedGoal = goal
                var newRuntimeState = goal.runtimeState ?? [:]
                newRuntimeState["check_ins"] = [:]  // Clear check-ins
                updatedGoal.runtimeState = newRuntimeState
                self.goal = updatedGoal
            }

            // Also refresh the full goal from the API for complete data
            Task {
                guard let baseURL = session.serverURL else { return }
                let client = APIClient(
                    baseURL: baseURL,
                    deviceTokenProvider: { session.deviceToken },
                    userTokenProvider: { session.userToken }
                )
                do {
                    let updatedGoal = try await client.getGoal(id: goal.id)
                    await MainActor.run {
                        self.goal = Goal.from(resource: updatedGoal)
                    }
                } catch {
                    print("[GoalView] Failed to refresh goal: \(error)")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top bar with counts, animation, and action buttons
            HStack(spacing: 16) {
                // Left: Task and Note counts (from goal, not paginated VMs)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(goal.tasksCount)")
                            .stat()
                            .foregroundColor(Color.accent(goal))
                        Text(goal.tasksCount == 1 ? "Task" : "Tasks")
                            .caption()
                            .foregroundColor(Color.accent(goal))
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(goal.notesCount)")
                            .stat()
                            .foregroundColor(Color.accent(goal))
                        Text(goal.notesCount == 1 ? "Note" : "Notes")
                            .caption()
                            .foregroundColor(Color.accent(goal))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                
                // Middle: Wave animation (flexible space)
                // Speed based on: agent working (active) or activity level (idle)
                let isAgentWorking = tasksVM.tasks.contains { $0.status == .active }
                let animationState: StatusAnimationState = isAgentWorking
                    ? .active
                    : .custom(speed: goal.activityLevel.animationSpeed)

                StatusAnimation(
                    type: .wave,
                    height: 30,
                    color: Color.accent(goal),
                    state: .constant(animationState)
                )
                .frame(maxWidth: .infinity)
                
                // Right: Three action buttons wrapped in single button
                Button(action: {
                    showingOptionsMenu = true
                }) {
                    HStack(spacing: 12) {
                        // Button 1: Diamond with wrench icon and count
                        VStack(spacing: 0) {
                            ZStack {
                                // Diamond shape
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 32, height: 32)
                                    .rotationEffect(.degrees(45))
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.accent(goal), lineWidth: 1.5)
                                            .rotationEffect(.degrees(45))
                                    )
                                
                                // Content
                                VStack(spacing: 1) {
                                    Image(systemName: "wrench.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(Color.accent(goal))
                                    Text("\(goal.enabledServersCount)")
                                        .bodySmall()
                                        .foregroundColor(Color.accent(goal))
                                }
                            }
                            .frame(width: 40, height: 44)
                        }

                        // Button 3: Pill with "OPT" and chevron
                        VStack(spacing: 0) {
                            VStack(spacing: 2) {
                                Text("OPT")
                                    .caption()
                                    .foregroundColor(Color.accent(goal))
                                Image(systemName: "chevron.down")
                                    .font(.symbol(size: 10))
                                    .foregroundColor(Color.accent(goal))
                            }
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(Color.accent(goal), lineWidth: 1.5)
                            )
                        }
                    }
                    .padding(.leading, 8)
                }
            }
            
            // Description below the header bar
            if let desc = goal.description, !desc.isEmpty {
                Text(desc)
                    .body()
                    .foregroundColor(Color.accent(goal))
            }

            // Check-in rows (scheduled and/or follow-up)
            // Uses timeRefreshTrigger to force re-render for live time updates
            checkInRows
                .id("checkIns-\(timeRefreshTrigger)")  // Force re-render on timer

            let activeTasks = tasksVM.tasks.filter { $0.status == .active || $0.status == .paused }
            if !activeTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activeTasks) { task in
                        Button {
                            selectedTaskId = task.id
                            showingTaskChat = true
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Color.accent(goal)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(task.title).bodyLarge().foregroundStyle(.primary)
                                        Spacer()
                                        Text(task.statusDisplayName)
                                            .caption()
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(task.statusColor.opacity(0.15))
                                            .foregroundColor(task.statusColor)
                                            .clipShape(Capsule())
                                    }
                                    if let ins = task.instructions, !ins.isEmpty {
                                        Text(ins).caption().foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    
                                    // Show retry info for paused tasks
                                    if task.status == .paused {
                                        HStack(spacing: 4) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(Color.semantic["warning"])
                                                .font(.symbol(size: 9))
                                            Text(task.userFriendlyErrorMessage)
                                                .caption()
                                                .foregroundColor(Color.semantic["warning"])
                                        }
                                        .padding(.top, 2)
                                        
                                        if !task.retryStatusText.isEmpty {
                                            Text(task.retryStatusText)
                                                .caption()
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    /// Shows check-in rows for scheduled and/or follow-up check-ins
    @ViewBuilder
    private var checkInRows: some View {
        let hasScheduled = goal.scheduledCheckIn != nil
        let hasFollowUp = goal.nextFollowUp != nil

        if hasScheduled || hasFollowUp {
            VStack(spacing: 8) {
                // Scheduled check-in row (from recurring schedule)
                if let scheduled = goal.scheduledCheckIn {
                    CheckInCard.scheduled(
                        scheduledFor: scheduled.scheduledFor,
                        scheduleText: goal.checkInSchedule?.displayText,
                        intent: scheduled.intent,
                        accentColor: Color.accent(goal)
                    )
                }

                // Follow-up row (one-time contextual)
                if let followUp = goal.nextFollowUp {
                    CheckInCard.followUp(
                        scheduledFor: followUp.scheduledFor,
                        intent: followUp.intent,
                        accentColor: Color.accent(goal)
                    )
                }
            }
        }
    }

    private var agentHelpBanner: some View {
        // Placeholder: Only visible when agent requires help
        Group {
            // Example hidden banner; set conditionally when you wire real agent state
            EmptyView()
        }
    }

    private var timeline: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            // Empty state when no notes or just the initial agent note
            // Only show after loading completes to prevent flash of empty state
            if !notesVM.loading && notesVM.notes.count <= 1 {
                emptyNotesState
            }

            ForEach(notesVM.notes) { note in
                Button {
                    navigationVM.openNote(id: note.id)
                } label: {
                    NoteCard(note: note, accentColor: Color.accent(goal))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if note.source == .user {
                        Button {
                            noteToEdit = note
                        } label: {
                            Label("Edit Note", systemImage: "pencil")
                        }
                    }

                    Button(role: .destructive) {
                        deleteNote(note)
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                }
            }

            // Infinite scroll - load more notes when reaching the bottom
            if notesVM.hasMoreNotes {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.accent(goal))
                        .onAppear {
                            Task {
                                await notesVM.loadMore()
                            }
                        }
                    Spacer()
                }
                .padding(.vertical, 16)
            }
        }
    }

    private var emptyNotesState: some View {
        VStack(spacing: 12) {
            Text("Add notes to \(goal.title) goal and agent will learn and add notes back, helping you progress toward your goal!")
                .body()
                .foregroundColor(Color.foreground["300"])
                .multilineTextAlignment(.center)

            Button {
                showingAddNote = true
            } label: {
                 HStack(spacing: 10) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add note")
                        .caption()
                }
                .foregroundColor(Color.accent(goal))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accent(goal), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.border["100"], lineWidth: 1)
        )
    }

    
    private func deleteNote(_ note: Note) {
        Task {
            do {
                try await notesVM.deleteNote(note)
                // Remove from local array
                notesVM.notes.removeAll { $0.id == note.id }
            } catch {
                // Handle error - could show an alert
                print("Failed to delete note: \(error)")
            }
        }
    }
    
    private func archiveGoal() {
        Task {
            // TODO: Implement archive API call
            // try await session.archiveGoal(goal.id)
            // Navigate back to home view
            print("Archive goal: \(goal.id)")
        }
    }
}
