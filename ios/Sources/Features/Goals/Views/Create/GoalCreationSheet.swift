import SwiftUI

/// View for goal creation chat interface
/// Uses unified ChatView with GoalCreationChatDataSource
struct GoalCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionManager.self) var session
    @State private var dataSource: GoalCreationChatDataSource
    @State private var chatViewModel: ChatViewModel

    var goalsVM: GoalsViewModel
    var onGoalCreated: (Goal) -> Void

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    /// Track if we restored from cache (to show Reset button)
    @State private var hasRestoredFromCache = false

    init(session: SessionManager, goalsVM: GoalsViewModel, onGoalCreated: @escaping (Goal) -> Void) {
        self.goalsVM = goalsVM
        self.onGoalCreated = onGoalCreated

        // Initialize data source and view model
        guard let baseURL = session.serverURL else {
            fatalError("Session must have a server URL")
        }

        let client = APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { session.deviceToken },
            userTokenProvider: { session.userToken }
        )

        let dataSource = GoalCreationChatDataSource(client: client)
        _dataSource = State(initialValue: dataSource)
        _chatViewModel = State(initialValue: ChatViewModel(
            session: session,
            dataSource: dataSource
        ))

        // Check if we have cached state to restore
        _hasRestoredFromCache = State(initialValue: GoalCreationChatDataSource.hasCachedState)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Use unified ChatView for message display
                ChatView(
                    viewModel: chatViewModel,
                    contentPadding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16),
                    showConversationHeaders: false,
                    headerContent: AnyView(
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "target")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)

                            Text("Chat back and forth to create a goal with Houston")
                                .title()
                                .foregroundStyle(Color.foreground["300"])

                            Text("Once the agent has what it needs, it will create the goal for you")
                                .body()
                                .foregroundStyle(Color.foreground["500"])

                            Divider()
                        }
                    )
                )

                // Inline input area (not footer-based like agent chats)
                ChatInput(
                    text: $inputText,
                    isFocused: $isInputFocused,
                    placeholder: "What would you like to achieve?",
                    isExpanded: true,
                    shouldFocusOnAppear: true,
                    onSend: sendMessage,
                    isSendDisabled: chatViewModel.isStreaming || dataSource.isCreatingGoal
                )
                .frame(height: 60)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .navigationTitle("Start new goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Save state for recovery (don't reset)
                        dataSource.saveToCache(messages: chatViewModel.messages)
                        dismiss()
                    }
                }

                // Show Reset button when there's actual conversation (not just greeting)
                if hasRestoredFromCache || chatViewModel.messages.contains(where: { $0.source == .user }) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Reset") {
                            withAnimation {
                                dataSource.resetConversation()
                                chatViewModel.messages = []
                                hasRestoredFromCache = false
                            }
                            // Reload to show initial greeting
                            Task {
                                await chatViewModel.loadHistory()
                            }
                        }
                    }
                }
            }
            .task {
                // Restore cached messages if available
                if let cachedMessages = dataSource.restoreCachedMessages() {
                    chatViewModel.messages = cachedMessages
                }
            }
            .navigationDestination(item: $dataSource.goalDataToPreview) { goalData in
                GoalFormView(
                    goalData: goalData,
                    onCancel: {
                        // Clear cache and dismiss the entire sheet
                        GoalCreationChatDataSource.clearCache()
                        dismiss()
                    },
                    onConfirm: { title, description, agentInstructions, learnings, enabledMcpServers, accentColor in
                        // Clear cache since goal is being created
                        GoalCreationChatDataSource.clearCache()

                        // Create goal optimistically - shows immediately
                        let optimisticGoal = goalsVM.createOptimistically(
                            title: title,
                            description: description,
                            agentInstructions: agentInstructions,
                            learnings: learnings,
                            enabledMcpServers: enabledMcpServers,
                            accentColor: accentColor
                        )

                        // Navigate to goal first, then dismiss sheet
                        // (dismiss after navigation to avoid SwiftUI timing conflicts)
                        onGoalCreated(optimisticGoal)
                        dismiss()
                    }
                )
                .environment(session)
            }
            .overlay {
                if dataSource.isCreatingGoal {
                    LoadingOverlay(message: "Writing goal details")
                }
            }
        }
        .environment(session)
    }

    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        inputText = ""
        chatViewModel.input = message

        Task {
            await chatViewModel.send()
        }
    }
}
