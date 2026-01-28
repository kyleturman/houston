import SwiftUI
import SwiftUINavigationTransitions

/// Primary navigation container managing app-wide navigation state.
///
/// Responsibilities:
/// - Route between app sections (goals, home, history)
/// - Manage sheet presentation (chat, forms, notes)
/// - Coordinate footer position with overlaid sheets

struct MainNavigationContainer: View {
    @Environment(SessionManager.self) var session
    @Environment(StateManager.self) var stateManager
    @Environment(NetworkMonitor.self) var networkMonitor
    @Namespace private var noteTransition

    // Core state
    @State private var navigationVM: NavigationViewModel
    @State private var goalsVM: GoalsViewModel

    // Other sheets
    @State private var showManualGoalForm = false
    
    // Chat sheet
    @State private var showChatSheet = false
    @State private var currentChatViewModel: ChatViewModel? // Used for both goal and home chat
    @State private var chatPreloadTask: Task<Void, Never>? // Debounced preload task
    
    // Screen metrics
    @State private var screenWidth: CGFloat = 0
    @State private var footerMinY: CGFloat = 0 // Track footer position for chat sheet
    private let visibleContentWidthWhenMenuOpen: CGFloat = 48

    // Notes
    @State private var noteToRecover: Note? = nil
    @State private var recoveryErrorMessage: String? = nil
    @State private var initialNoteContent: String? = nil


    init() {
        // Initialize ViewModels with placeholder session - will be replaced via setSession() in .task
        // Use skipLoad: true to prevent the placeholder from loading persisted data (which would cause loops)
        let goalsViewModel = GoalsViewModel(session: SessionManager(skipLoad: true))
        _goalsVM = State(initialValue: goalsViewModel)
        _navigationVM = State(initialValue: NavigationViewModel(goalsViewModel: goalsViewModel))
    }

    var body: some View {
        mainView
            .sheet(isPresented: $showManualGoalForm) {
                manualGoalFormSheet
            }
            .sheet(isPresented: $navigationVM.showingNoteCompose) {
                let initialGoal = navigationVM.goalForNoteCompose ?? currentGoal
                let _ = print("📋 [MainNav] Sheet opening with initialGoal: \(initialGoal?.title ?? "nil"), goalForNoteCompose: \(navigationVM.goalForNoteCompose?.title ?? "nil"), currentGoal: \(currentGoal?.title ?? "nil")")

                NoteComposeSheetView(
                    initialGoal: initialGoal,
                    existingNote: noteToRecover,
                    isRecoveryMode: noteToRecover != nil,
                    initialContent: initialNoteContent,
                    initialErrorMessage: recoveryErrorMessage,
                    onCreated: { newNote in
                        // Note created - clear recovery state and shared content (StateManager will auto-refresh)
                        noteToRecover = nil
                        recoveryErrorMessage = nil
                        initialNoteContent = nil
                        navigationVM.goalForNoteCompose = nil // Clear the temporary goal
                    },
                    onCreateFailed: { failedNote, errorMessage in
                        // Save failed - set up for recovery
                        noteToRecover = failedNote
                        recoveryErrorMessage = errorMessage
                        // Re-open sheet after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            navigationVM.showingNoteCompose = true
                        }
                    }
                )
                .presentationDetents([.large])
                .navigationTransition(.zoom(sourceID: navigationVM.noteComposeSourceID, in: noteTransition))
                .environment(session)
                .environment(navigationVM)
            }
            .background(
                LinearGradient(
                    colors: navigationVM.showingSideMenu ? [Color.background["200"], Color.background["100"]] : [Color.background["000"]],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .animation(.easeInOut(duration: navigationVM.showingSideMenu ? 0 : 0.15), value: navigationVM.showingSideMenu)
            )
    }
    
    private var mainView: some View {
        let stack = ZStack {
            settingsMenu
            mainContentContainer
        }

        return stack
        .clipped()
        .task(id: "\(session.serverURL?.absoluteString ?? ""):\(session.userToken != nil)") {
            // Guard: Don't proceed if session isn't fully configured
            guard session.serverURL != nil else {
                print("[MainNavigationContainer] Skipping task - no server URL")
                return
            }

            // Load goals whenever server changes or auth state changes (signed in/out)
            // Uses token presence (not value) to avoid re-running on token refresh
            goalsVM.setSession(session)
            // Non-blocking: Task inherits parent cancellation (unlike Task.detached)
            Task {
                await goalsVM.load()
                navigationVM.syncSelectedItem()
            }

            // Preload chat ViewModel for current context using pool (no SSE yet)
            let context: AgentChatDataSource.Context = if let goal = currentGoal {
                .goal(id: goal.id)
            } else {
                .userAgent
            }
            currentChatViewModel = ChatViewModelPool.shared.get(
                context: context,
                session: session,
                goal: currentGoal
            )
            // Preload messages without starting SSE stream
            Task {
                await currentChatViewModel?.initializeWithoutStream()
            }
        }
        .onChange(of: currentGoalId) { _, _ in
            // Stop SSE and clear VM on goal change
            currentChatViewModel?.stopStream()
            currentChatViewModel = nil

            // Guard: Don't proceed if session isn't fully configured
            guard session.serverURL != nil else { return }

            // Cancel any pending preload and debounce the new one
            // This prevents API spam when user swipes rapidly between goals
            chatPreloadTask?.cancel()
            chatPreloadTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }

                let context: AgentChatDataSource.Context = if let goal = currentGoal {
                    .goal(id: goal.id)
                } else {
                    .userAgent
                }
                currentChatViewModel = ChatViewModelPool.shared.get(
                    context: context,
                    session: session,
                    goal: currentGoal
                )
                await currentChatViewModel?.initializeWithoutStream()
            }
        }
        .onChange(of: showChatSheet) { _, isShowing in
            if isShowing {
                // Guard: Don't proceed if session isn't fully configured
                guard session.serverURL != nil else {
                    showChatSheet = false
                    return
                }

                // Cancel pending preload - we need the VM immediately
                chatPreloadTask?.cancel()

                // Ensure ViewModel exists (pool may have it cached with messages already)
                if currentChatViewModel == nil {
                    let context: AgentChatDataSource.Context = if let goal = currentGoal {
                        .goal(id: goal.id)
                    } else {
                        .userAgent
                    }
                    currentChatViewModel = ChatViewModelPool.shared.get(
                        context: context,
                        session: session,
                        goal: currentGoal
                    )
                    // Note: If cache miss, ChatView.task will call initialize() to load messages
                }
                // Start SSE stream for real-time updates
                currentChatViewModel?.startStream()
            } else {
                // Sheet closing - stop SSE but keep ViewModel cached
                currentChatViewModel?.stopStream()
            }
        }
        // MARK: - Real-time Updates via StateManager
        .onReceive(stateManager.goalCreatedPublisher) { _ in
            Task {
                await goalsVM.load()
                navigationVM.syncSelectedItem()
            }
        }
        .onReceive(stateManager.goalUpdatedPublisher) { event in
            print("🔄 [MainNav] Received goal_updated for ID: \(event.goal_id), starting reload...")
            Task {
                await goalsVM.load()
                navigationVM.syncSelectedItem()
                print("✅ [MainNav] Reload complete")
            }
        }
        .onReceive(stateManager.goalArchivedPublisher) { _ in
            Task {
                await goalsVM.load()
                navigationVM.syncSelectedItem()
            }
        }
        // MARK: - Handle optimistic goal replacement
        // When an optimistic goal is saved to server, update selectedItem if needed
        .onReceive(goalsVM.optimisticGoalReplacedPublisher) { tempId, realGoal in
            if case .goal(let currentGoal) = navigationVM.selectedItem,
               currentGoal.id == tempId {
                // The currently selected goal was the optimistic one - update to real goal
                navigationVM.selectItem(.goal(realGoal))
            }
        }
        // MARK: - Auto-refresh on network restoration
        .onReceive(stateManager.dataRefreshNeededPublisher) { _ in
            Task {
                await goalsVM.load()
                navigationVM.syncSelectedItem()
            }
        }
        // MARK: - Handle shared content from Share Extension
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowNoteComposeWithSharedContent"))) { notification in
            if let userInfo = notification.userInfo {
                let url = userInfo["url"] as? String
                let text = userInfo["text"] as? String

                // Set initial content (prefer URL over text)
                if let url = url {
                    initialNoteContent = url
                } else if let text = text {
                    initialNoteContent = text
                }

                // Show the note compose sheet
                navigationVM.showingNoteCompose = true
            }
        }
        // MARK: - Handle navigation to goal from Share Extension
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToGoal"))) { notification in
            guard let goalId = notification.userInfo?["goalId"] as? String,
                  let goal = goalsVM.goals.first(where: { $0.id == goalId }) else {
                print("[MainNavigationContainer] Could not find goal for ID")
                return
            }
            navigationVM.selectItem(.goal(goal))
        }
        // MARK: - Handle navigation to history from Share Extension
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHistory"))) { _ in
            navigationVM.navigateToHistory()
        }
        // MARK: - Handle navigation to feed from push notification
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToFeed"))) { _ in
            navigationVM.selectItem(.home)
        }
        .environment(navigationVM)
    }

    private var mainContentContainer: some View {
        ZStack(alignment: .bottom) {
            NavigationStack(path: $navigationVM.navigationPath) {
                VStack(spacing: 0) {
                    // Connectivity banner at the top (pushes content down)
                    if networkMonitor.showBanner {
                        ConnectivityBanner(status: networkMonitor.status)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(1)  // Ensure banner stays on top
                    }

                    HorizontalNavigationBar(navigationVM: navigationVM)
                    ContentContainer(navigationVM: navigationVM, noteTransition: noteTransition)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.95),
                            .init(color: .clear, location: 0.975)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.top, 4)
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .history:
                        ActivityView()
                            .environment(session)
                            .environment(stateManager)
                            .environment(navigationVM)
                            .navigationTransition(.fade(.in).animation(.easeOut(duration: 0.2)))
                    case .notes:
                        NotesView()
                            .environment(session)
                            .environment(stateManager)
                            .environment(navigationVM)
                            .navigationTransition(.fade(.in).animation(.easeOut(duration: 0.2)))
                    case .goalsManagement:
                        GoalsManagementView()
                            .environment(session)
                            .environment(navigationVM)
                            .navigationTransition(.fade(.in).animation(.easeOut(duration: 0.2)))
                    }
                }
                .environment(navigationVM)
            }
            .sheet(item: $navigationVM.activeSheet) { sheet in
                // Guard: Dismiss sheet if session becomes invalid
                if session.serverURL == nil {
                    Color.clear.onAppear { navigationVM.activeSheet = nil }
                } else {
                    switch sheet {
                    case .note(let id):
                        NoteDetailSheetView(noteId: id)
                            .environment(session)
                            .environment(navigationVM)
                    case .task(let id):
                        TaskChatSheetView(taskId: id)
                            .environment(session)
                            .environment(navigationVM)
                    case .goalCreation:
                        goalCreationChatSheet
                    }
                }
            }
            .overlay {
                // FooterChatSheet - Full screen, stays fixed, ignores keyboard, behind FooterActionBar
                FooterChatSheet(
                    isPresented: $showChatSheet,
                    footerMinY: $footerMinY,
                    chatViewModel: currentChatViewModel,
                    currentGoal: currentGoal
                )
                .ignoresSafeArea(.all)
                .ignoresSafeArea(.keyboard)
            }
            .ignoresSafeArea(.all)
            .safeAreaInset(edge: .bottom) {
                // FooterActionBar - Moves with keyboard via safeAreaInset
                FooterActionBar(
                    currentGoal: currentGoal,
                    showChatSheet: $showChatSheet,
                    showNoteComposeSheet: $navigationVM.showingNoteCompose,
                    footerMinY: $footerMinY,
                    chatViewModel: showChatSheet ? currentChatViewModel : nil,
                    noteTransition: noteTransition
                )
                .zIndex(3000)
                .modifier(DeepNavigationHideModifier(isInDeepNavigation: navigationVM.isInDeepNavigation))
            }

            // Overlay to close menu when tapping outside
            Color.black.opacity(navigationVM.showingSideMenu ? 0.8 : 0)
                .allowsHitTesting(navigationVM.showingSideMenu)
                .onTapGesture {
                    navigationVM.closeSideMenu()
                }
                .zIndex(3001)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: navigationVM.showingSideMenu ? 24 : 0)
        )
        .offset(x: navigationVM.showingSideMenu ? -(screenWidth - visibleContentWidthWhenMenuOpen) : 0)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        screenWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        screenWidth = newWidth
                    }
            }
        )
        .zIndex(10)
    }

    private var settingsMenu: some View {
        SettingsView(onCreateGoal: navigationVM.openGoalCreation)
            .padding(.leading, visibleContentWidthWhenMenuOpen)
            .environment(session)
            .environment(navigationVM)
            .zIndex(1)
            .opacity(navigationVM.showingSideMenu ? 1.0 : 0.0)
            .offset(x: navigationVM.showingSideMenu ? 0 : 32)
            .scaleEffect(navigationVM.showingSideMenu ? 1.0 : 0.95)       
    }

    private var goalCreationChatSheet: some View {
        GoalCreationSheet(
            session: session,
            goalsVM: goalsVM,
            onGoalCreated: { goal in
                // Goal already added optimistically by goalsVM
                navigationVM.selectItem(.goal(goal))
            }
        )
        .environment(session)
        .environment(navigationVM)
    }
    
    private var manualGoalFormSheet: some View {
        GoalFormView(
            goalData: GoalDataPreview(
                title: "",
                description: "",
                agentInstructions: "",
                learnings: [],
                enabledMcpServers: []
            ),
            onCancel: {
                showManualGoalForm = false
            },
            onConfirm: { title, description, agentInstructions, learnings, enabledMcpServers, accentColor in
                Task {
                    let success = await goalsVM.create(
                        title: title,
                        description: description,
                        agentInstructions: agentInstructions,
                        learnings: learnings,
                        enabledMcpServers: enabledMcpServers,
                        accentColor: accentColor
                    )
                    if success {
                        showManualGoalForm = false
                        if let newGoal = goalsVM.goals.first {
                            navigationVM.selectItem(.goal(newGoal))
                        }
                    }
                }
            }
        )
        .environment(ThemeManager.shared)
        .environment(session)
    }

    private var currentGoal: Goal? {
        switch navigationVM.selectedItem {
        case .goal(let goal):
            return goal
        case .home:
            return nil
        default:
            return nil
        }
    }

    private var currentGoalId: String? {
        currentGoal?.id
    }
}

// MARK: - Custom Modifier to Isolate Deep Navigation Animation
//
// This modifier isolates the deep navigation animation from keyboard animations.
//
// **Why this exists:**
// The FooterActionBar has two independent animation needs:
// 1. Keyboard animations (via KeyboardAwareWrapper) - should use keyboard's timing
// 2. Deep navigation hide/show - should use custom spring animation
//
// If we used a blanket `.animation()` modifier on the FooterActionBar, it would animate
// EVERY change, including keyboard constraint updates from KeyboardAwareWrapper. This would
// override the keyboard's natural timing and cause jank.
//
// By wrapping the opacity/offset in a custom ViewModifier with `.animation(value:)`, we ensure
// it ONLY animates when `isInDeepNavigation` changes, not when keyboard constraints change.
//
// **Key Principle:**
// Use `.animation(value:)` (not `.animation()`) when you need selective animation of specific
// properties while leaving other animations (like keyboard) to handle themselves.

struct DeepNavigationHideModifier: ViewModifier {
    let isInDeepNavigation: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isInDeepNavigation ? 0 : 1)
            .offset(y: isInDeepNavigation ? 100 : 0)
            .animation(
                isInDeepNavigation ?
                    .easeOut(duration: 0.1) :
                    .spring(response: 0.4, dampingFraction: 0.6),
                value: isInDeepNavigation  // ONLY animate when this value changes
            )
    }
}
