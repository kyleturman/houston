import SwiftUI

struct SessionHistoryView: View {
    @Environment(StateManager.self) private var stateManager
    @State private var vm: SessionHistoryViewModel
    @State private var sessionToDelete: AgentHistory?
    @State private var showingDeleteConfirmation = false
    @State private var showingResetConfirmation = false

    private let client: APIClient
    private let goalId: String?
    private let isUserAgent: Bool

    init(goalId: String?, isUserAgent: Bool = false, client: APIClient) {
        self.client = client
        self.goalId = goalId
        self.isUserAgent = isUserAgent
        self._vm = State(initialValue: SessionHistoryViewModel(
            goalId: goalId,
            isUserAgent: isUserAgent,
            client: client
        ))
    }

    var body: some View {
        NavigationStack {
            contentView
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .task {
                    await vm.loadCurrentSession()
                    await vm.loadSessions()
                }
                .onReceive(stateManager.agentHistoryDeletedPublisher, perform: handleHistoryDeleted)
                .onReceive(stateManager.agentSessionResetPublisher, perform: handleSessionReset)
                .presentationDragIndicator(.visible)
                .alert("Delete Session", isPresented: $showingDeleteConfirmation, presenting: sessionToDelete) { session in
                    deleteConfirmationButtons(for: session)
                } message: { _ in
                    Text("Are you sure you want to delete this session? This will also delete all messages in the session.")
                }
                .alert("Error", isPresented: errorAlertBinding) {
                    Button("OK") { vm.errorMessage = nil }
                } message: {
                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                    }
                }
                .alert("Reset Current Session", isPresented: $showingResetConfirmation) {
                    resetConfirmationButtons
                } message: {
                    Text("This will clear the current conversation context. The agent will start fresh with no memory of this session.")
                }
        }
    }

    // MARK: - View Components

    @ViewBuilder
    private var contentView: some View {
        if vm.isLoading && vm.sessions.isEmpty && vm.currentSession == nil {
            ProgressView("Loading sessions...")
        } else if vm.sessions.isEmpty && vm.currentSession == nil {
            ContentUnavailableView(
                "No Session History",
                systemImage: "clock.arrow.circlepath",
                description: Text("Past conversation sessions will appear here")
            )
        } else {
            sessionList
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                Text("Session History")
            }
        }
    }

    // MARK: - Alert Buttons

    @ViewBuilder
    private func deleteConfirmationButtons(for session: AgentHistory) -> some View {
        Button("Cancel", role: .cancel) {
            sessionToDelete = nil
        }
        Button("Delete", role: .destructive) {
            Task {
                await vm.deleteSession(session)
                sessionToDelete = nil
            }
        }
    }

    @ViewBuilder
    private var resetConfirmationButtons: some View {
        Button("Cancel", role: .cancel) { }
        Button("Reset", role: .destructive) {
            Task {
                await vm.resetCurrentSession()
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding.constant(vm.errorMessage != nil)
    }

    // MARK: - Event Handlers

    private func handleHistoryDeleted(_ event: StateManager.AgentHistoryDeletedEvent) {
        let isRelevant = isEventRelevant(agentableType: event.agentable_type, agentableId: event.agentable_id)
        if isRelevant {
            vm.handleSessionDeleted(historyId: String(event.agent_history_id))
        }
    }

    private func handleSessionReset(_ event: StateManager.AgentSessionResetEvent) {
        let isRelevant = isEventRelevant(agentableType: event.agentable_type, agentableId: event.agentable_id)
        if isRelevant {
            vm.handleSessionReset()
        }
    }

    private func isEventRelevant(agentableType: String, agentableId: Int) -> Bool {
        if isUserAgent {
            return agentableType == "UserAgent"
        } else if let goalId = goalId {
            return agentableType == "Goal" && String(agentableId) == goalId
        } else {
            return false
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        List {
            Text("Conversation session history is automatically summarized to maintain context.")
                .body()
                .foregroundColor(Color.foreground["500"])
                .listRowSeparator(.hidden)
                .padding(.top, -8)
                .padding(.trailing, -8)
                .padding(.bottom, -12)

            // Current session (in-progress)
            if let currentSession = vm.currentSession {
                Section {
                    NavigationLink {
                        SessionDetailView(
                            session: currentSession,
                            goalId: goalId,
                            isUserAgent: isUserAgent,
                            client: client
                        )
                    } label: {
                        CurrentSessionRow(session: currentSession)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                showingResetConfirmation = true
                            }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    }
                } header: {
                    Text("Current Session")
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                }
            }

            // Archived sessions
            if !vm.sessions.isEmpty {
                Section {
                    ForEach(vm.sessions) { session in
                        NavigationLink {
                            SessionDetailView(
                                session: session,
                                goalId: goalId,
                                isUserAgent: isUserAgent,
                                client: client
                            )
                        } label: {
                            SessionRow(session: session)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                // Disable animations to prevent list jitter when showing alert
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    sessionToDelete = session
                                    showingDeleteConfirmation = true
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Past Sessions")
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                }
            }
        }
        .listStyle(.plain)
    }
}

/// Row view for current (in-progress) session
private struct CurrentSessionRow: View {
    let session: AgentHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // In Progress badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                Text("In Progress")
                    .caption()
                    .fontWeight(.medium)
                    .foregroundStyle(Color.blue)
            }

            // Summary
            Text("Current conversation session")
                .font(.body)
                .foregroundStyle(Color.foreground["700"])

            // Metadata
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.foreground["500"])
                    Text("\(session.messageCount)")
                        .caption()
                        .foregroundStyle(Color.foreground["500"])
                }

                Text("Swipe to reset context")
                    .caption()
                    .foregroundStyle(Color.foreground["400"])
            }
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
        .alignmentGuide(VerticalAlignment.center) { d in d[.top] + 12 }
    }
}

/// Row view for a single session
private struct SessionRow: View {
    let session: AgentHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Summary
            Text(session.summary)
                .font(.body)
                .lineLimit(2)

            // Metadata
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.foreground["500"])
                    Text("\(session.messageCount)")
                        .caption()
                        .foregroundStyle(Color.foreground["500"])
                }

                Text(session.sessionDateString)
                    .caption()
                    .foregroundStyle(Color.foreground["500"])
            }
        }
        .padding(.vertical, 4)
        // Align chevron to first line by shifting the vertical center point up
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
        .alignmentGuide(VerticalAlignment.center) { d in d[.top] + 12 }
    }

    private var formattedTokens: String {
        if session.tokenCount >= 1000 {
            return String(format: "%.1fk", Double(session.tokenCount) / 1000.0)
        } else {
            return "\(session.tokenCount)"
        }
    }
}
