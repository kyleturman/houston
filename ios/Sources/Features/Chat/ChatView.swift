import SwiftUI

struct ChatView: View {
    @Environment(SessionManager.self) var session
    @Environment(NavigationViewModel.self) var navigationVM
    @Bindable var vm: ChatViewModel
    @Environment(\.chatScrollInsets) private var environmentInsets

    // Optional parameters for linear chat support
    var linearDataSource: (any ObservableObject)?
    var onLinearChatComplete: ((Any) -> Void)?

    // Scroll configuration
    var topInset: CGFloat? = nil
    var bottomInset: CGFloat? = nil
    var contentPadding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    var onScrollPositionChanged: ((CGFloat, Bool) -> Void)?

    // Display configuration
    var showConversationHeaders: Bool = true
    var headerContent: AnyView? = nil

    private let scrollThreshold: CGFloat = 10

    // Scroll position using iOS 17+ ScrollPosition API
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    // Track anchor for scroll restoration after loading more
    @State private var scrollAnchorId: String?

    // Height of the "Load more" button area (button content + vertical padding)
    private let loadMoreButtonHeight: CGFloat = 44

    // Computed insets: prefer explicit parameters, fall back to environment
    // Ensure values are always valid (non-negative and finite)
    private var computedTopInset: CGFloat {
        let value = topInset ?? environmentInsets.top
        return max(0, value.isFinite ? value : 0)
    }

    private var computedBottomInset: CGFloat {
        let value = bottomInset ?? environmentInsets.bottom
        return max(0, value.isFinite ? value : 0)
    }

    /// Binding for error alert that properly clears errorMessage when dismissed
    private var errorBinding: Binding<LocalizedErrorWrapper?> {
        Binding(
            get: { vm.errorMessage.map { LocalizedErrorWrapper(message: $0) } },
            set: { _ in vm.errorMessage = nil }
        )
    }

    init(viewModel: ChatViewModel,
         linearDataSource: (any ObservableObject)? = nil,
         onLinearChatComplete: ((Any) -> Void)? = nil,
         topInset: CGFloat? = nil,
         bottomInset: CGFloat? = nil,
         contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16),
         onScrollPositionChanged: ((CGFloat, Bool) -> Void)? = nil,
         showConversationHeaders: Bool = true,
         headerContent: AnyView? = nil) {
        self.vm = viewModel
        self.linearDataSource = linearDataSource
        self.onLinearChatComplete = onLinearChatComplete
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.contentPadding = contentPadding
        self.onScrollPositionChanged = onScrollPositionChanged
        self.showConversationHeaders = showConversationHeaders
        self.headerContent = headerContent
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    messageListContent
                        .scrollTargetLayout()
                        .padding(contentPadding)
                        .frame(maxWidth: .infinity)

                    // Invisible anchor at bottom for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .scrollIndicators(.visible)
                .scrollPosition($scrollPosition)
                .defaultScrollAnchor(.bottom)
                .coordinateSpace(name: "scroll")
                .safeAreaPadding(.top, computedTopInset)
                .safeAreaPadding(.bottom, computedBottomInset)
                .onChange(of: scrollAnchorId) { _, newId in
                    // Scroll to anchor after loading more sessions
                    if let id = newId {
                        print("[ChatView] onChange fired, scrolling to: \(id)")
                        // Small delay to let SwiftUI lay out new content
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            print("[ChatView] Executing scrollTo for: \(id)")
                            proxy.scrollTo(id, anchor: .top)
                            scrollAnchorId = nil
                        }
                    }
                }
                .onChange(of: vm.messages.count) { oldCount, newCount in
                    // When user sends a message, scroll to the bottom edge
                    // This ensures we're "at the bottom" so defaultScrollAnchor(.bottom) will
                    // keep us there as the typing indicator and response stream in
                    guard newCount > oldCount,
                          let lastMsg = vm.messages.last,
                          lastMsg.source == .user else { return }

                    // Brief delay to ensure layout is complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            // Use ScrollPosition.scrollTo(edge:) - properly handles safe area
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    }
                }
            }

            // Show retry banner for paused tasks
            if vm.shouldShowRetryBanner, let task = vm.currentTask {
                RetryBanner(task: task) {
                    Task { await vm.retryTask() }
                }
            }
        }
        .task {
            vm.setSession(session)
            // Non-blocking: Task inherits parent cancellation (unlike Task.detached)
            Task { await vm.initialize() }
        }
        .onDisappear { vm.stopStream() }
        .alert(item: errorBinding) { w in
            Alert(
                title: Text("Error"),
                message: Text(w.message),
                primaryButton: .default(Text("Retry")) { Task { await vm.retryLast() } },
                secondaryButton: .cancel(Text("OK"))
            )
        }
    }

    /// Structure to hold a day group of messages
    private struct DayGroup: Identifiable {
        let id: String // date string (YYYY-MM-DD)
        let date: Date
        let messages: [ChatMessage]

        var displayTitle: String {
            let calendar = Calendar.current
            if calendar.isDateInToday(date) {
                return "Today"
            } else if calendar.isDateInYesterday(date) {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return formatter.string(from: date)
            }
        }
    }

    /// Group messages by day
    private func groupMessagesByDay() -> [DayGroup] {
        let calendar = Calendar.current
        var dayGroups: [String: [ChatMessage]] = [:]

        // Group messages by day
        for message in vm.messages {
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: message.createdAt)

            let dateKey = String(format: "%04d-%02d-%02d",
                                dateComponents.year ?? 0,
                                dateComponents.month ?? 0,
                                dateComponents.day ?? 0)
            dayGroups[dateKey, default: []].append(message)
        }

        // Convert to DayGroup array, sorted by date (oldest first)
        let groups = dayGroups.map { key, messages -> DayGroup in
            let sortedMessages = messages.sorted { $0.createdAt < $1.createdAt }
            let date = sortedMessages.first?.createdAt ?? Date()
            return DayGroup(id: key, date: date, messages: sortedMessages)
        }.sorted { $0.date < $1.date }

        return groups
    }

    @ViewBuilder
    private var messageListContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Optional header content (scrolls with messages)
            if let header = headerContent {
                header
                    .padding(.bottom, 8)
            }

            // Top scroll indicator
            if vm.isLoadingMoreSessions {
                // Loading more sessions
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading earlier messages...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 12)
                .id("loading-indicator")
            } else if vm.hasMoreSessions {
                // Has more sessions - show load more button
                Button {
                    // Always capture the first message ID (not button/header IDs)
                    let anchorId = vm.messages.first?.id
                    print("[ChatView] Load more tapped, anchor: \(anchorId ?? "nil")")
                    Task {
                        await vm.loadMoreSessions()
                        // After loading, scroll to the anchor message
                        if let id = anchorId {
                            print("[ChatView] Setting scrollAnchorId to: \(id)")
                            scrollAnchorId = id
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.circle")
                            .font(.caption)
                        Text("Load earlier messages (\(vm.totalSessions - vm.loadedSessions) more sessions)")
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .id("load-more-button")
            } else if !vm.messages.isEmpty && showConversationHeaders {
                // No more sessions - show beginning marker
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.to.line")
                            .font(.caption2)
                        Text("Beginning of conversation")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
                    Spacer()
                }
                .id("beginning-marker")
            }

            // Group messages by day
            let dayGroups = groupMessagesByDay()
            ForEach(dayGroups) { group in
                // Day header (only show if showConversationHeaders is true)
                if showConversationHeaders {
                    VStack(spacing: 0) {
                        Text(group.displayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .id("day-header-\(group.id)")
                }

                // Messages in this day
                ForEach(group.messages) { msg in
                    messageView(for: msg)
                }
            }

            // Show typing indicator when waiting for agent's first response
            // Conditions: streaming AND either last message is from user OR last message is empty agent response
            // (empty agent message is added on .start event, before first chunk arrives)
            if vm.isStreaming && (vm.messages.last?.source == .user ||
                (vm.messages.last?.source == .agent && vm.messages.last?.content.isEmpty == true)) {
                HStack(spacing: 8) {
                    TypingIndicator()
                }
                // Match MessageBubble agent padding for smooth transition
                .padding(.leading, 2)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
                .id("streaming-indicator")
            }
        }
    }

    /// Check if we should show a date divider before this message
    private func shouldShowDateDivider(for message: ChatMessage, in sessionMessages: [ChatMessage]) -> Bool {
        guard let index = sessionMessages.firstIndex(where: { $0.id == message.id }),
              index > 0 else {
            return false // Don't show divider for first message in session
        }

        let previousMessage = sessionMessages[index - 1]
        let calendar = Calendar.current
        return !calendar.isDate(message.createdAt, inSameDayAs: previousMessage.createdAt)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    @ViewBuilder
    private func messageView(for msg: ChatMessage) -> some View {
        // Skip empty streaming messages (typing indicator handles this state)
        if msg.isStreaming && msg.content.isEmpty {
            EmptyView()
        }
        // Check if message has special cell content (tool)
        // Only user-facing tools create ThreadMessages (backend enforces this)
        else if msg.tool != nil {
            ChatCellView(
                message: msg,
                actions: ChatCellActions(
                    onOpenTask: { taskId in navigationVM.openTask(id: taskId) },
                    onOpenNote: { noteId in navigationVM.openNote(id: noteId) },
                    goal: vm.currentGoal
                ),
                isTaskContext: vm.isTaskContext
            )
            .id(msg.id)
        } else if msg.source == .error {
            // Error messages from system failures
            ErrorMessageView(
                message: msg,
                onRetry: {
                    Task { await vm.retryErrorMessage(messageId: msg.id) }
                },
                onDismiss: {
                    Task { await vm.dismissErrorMessage(messageId: msg.id) }
                }
            )
            .transition(.asymmetric(
                insertion: .opacity,
                removal: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top))
            ))
            .id(msg.id)
        } else {
            MessageBubble(message: msg)
                .transition(.opacity)
                .id(msg.id)
        }
    }

}

private struct LocalizedErrorWrapper: Identifiable { let id = UUID(); let message: String }

/// Date divider view to show when date changes in chat
private struct DateDividerView: View {
    let date: Date

    var body: some View {
        HStack {
            Spacer()
            Text(formattedDate)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var formattedDate: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

struct ChatScrollInsetsKey: EnvironmentKey {
    static let defaultValue = (top: CGFloat(0), bottom: CGFloat(0))
}

extension EnvironmentValues {
    var chatScrollInsets: (top: CGFloat, bottom: CGFloat) {
        get { self[ChatScrollInsetsKey.self] }
        set { self[ChatScrollInsetsKey.self] = newValue }
    }
}

/// Preference key for tracking scroll offset
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
