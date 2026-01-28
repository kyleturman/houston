import SwiftUI
import Combine

struct HomeView: View {
    @Environment(SessionManager.self) var sessionManager
    @Environment(StateManager.self) var stateManager
    @Environment(NavigationViewModel.self) var navigationVM
    @State private var loadingFeed = false
    @State private var feedData: FeedResponse?
    @State private var feedError: Error?
    @State private var feedSchedule: FeedSchedule?
    @State private var isInitializing = true
    @State private var hasCheckedInitialGoals = false
    @State private var hasGoals = false
    @State private var showingIntegrations = false
    @State private var gradientPhase: CGFloat = 0

    let noteTransition: Namespace.ID

    var body: some View {
        Group {
            if isInitializing {
                // Show nothing while checking initial state to prevent flash
                Color.background["000"]
            } else if !hasGoals {
                // No goals → show welcome empty state
                welcomeEmptyState
            } else {
                // Has goals → show feed UI
                ScrollView {
                    VStack(spacing: 16) {
                        // Feed header with user name, goals count, and timeline widget
                        FeedHeaderView(
                            userName: sessionManager.currentUserName,
                            goalCount: navigationVM.goalsVM.goals.count,
                            hasActiveAgents: navigationVM.goalsVM.goals.contains(where: { $0.status == .working }),
                            goals: navigationVM.goalsVM.goals,
                            feedItems: feedData?.items,
                            feedSchedule: $feedSchedule,
                            noteTransition: noteTransition
                        )

                        // Feed content or loading
                        // Show spinner when no data and no error (still loading)
                        if let error = feedError {
                            // Error state - show helpful message
                            VStack(spacing: 12) {
                                Text("Unable to load feed")
                                    .bodyLarge()
                                    .foregroundColor(Color.foreground["300"])

                                Text("Try pulling down to refresh")
                                    .bodySmall()
                                    .foregroundColor(Color.foreground["200"])

                                if error is DecodingError {
                                    Text("Data format mismatch - try clearing cache in Settings")
                                        .caption()
                                        .foregroundColor(Color.foreground["200"])
                                        .multilineTextAlignment(.center)
                                        .padding(.top, 8)
                                }
                            }
                            .multilineTextAlignment(.center)
                            .padding(.top, 40)
                            .padding(.horizontal, 16)
                        } else if let feed = feedData {
                            feedContent(feed)
                        } else {
                            // Loading state - no data yet and no error
                            ProgressView()
                                .padding(.top, 40)
                        }
                    }
                    .padding(.bottom, 120) // Extra padding for floating footer
                }
                .refreshable {
                    await refreshFeed()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.background["000"])
            }
        }
        .task {
            // Wait for goals to load before checking if user has any
            // This prevents flashing empty state while goals are loading
            if !hasCheckedInitialGoals {
                // If goals haven't loaded yet, wait for them (max 5 seconds)
                if !navigationVM.goalsVM.hasLoadedOnce {
                    let maxWaitIterations = 100  // 50ms * 100 = 5 seconds max
                    var iterations = 0
                    while !navigationVM.goalsVM.hasLoadedOnce && iterations < maxWaitIterations {
                        try? await Task.sleep(for: .milliseconds(50))
                        iterations += 1
                    }
                }

                hasCheckedInitialGoals = true
                hasGoals = !navigationVM.goalsVM.goals.isEmpty

                if hasGoals {
                    // Load feed and schedule in parallel before revealing UI
                    async let feedTask: () = loadExistingFeed()
                    async let scheduleTask: () = loadFeedSchedule()
                    _ = await (feedTask, scheduleTask)
                }

                withAnimation(.easeIn(duration: 0.2)) {
                    isInitializing = false
                }
            }
        }
        .onChange(of: navigationVM.goalsVM.goals) { _, goals in
            // Update hasGoals when goals change (e.g., user creates first goal)
            let newHasGoals = !goals.isEmpty

            // If transitioning from no goals to having goals, load the feed and schedule
            if !hasGoals && newHasGoals {
                hasGoals = true
                Task {
                    async let feedTask: () = loadExistingFeed()
                    async let scheduleTask: () = loadFeedSchedule()
                    _ = await (feedTask, scheduleTask)
                }
            } else {
                hasGoals = newHasGoals
            }

            // Ensure we're not stuck in initializing state
            if isInitializing {
                withAnimation(.easeIn(duration: 0.2)) {
                    isInitializing = false
                }
            }
        }
        .onReceive(stateManager.feedInsightsReadyPublisher) { _ in
            // Auto-refresh feed when insights are generated
            Task { await loadExistingFeed() }
        }
        .onReceive(stateManager.noteCreatedPublisher) { event in
            // Auto-refresh feed when any note is created (will show if it's an agent note)
            Task { await loadExistingFeed() }
        }
        .onReceive(stateManager.noteUpdatedPublisher) { event in
            // Auto-refresh feed when a note is updated
            Task { await loadExistingFeed() }
        }
        .onReceive(stateManager.dataRefreshNeededPublisher) { _ in
            // Refresh feed when app returns from background (SSE reconnection)
            guard hasGoals else { return }
            Task { await loadExistingFeed() }
        }
    }

    private func loadExistingFeed() async {
        // Prevent concurrent loads
        guard !loadingFeed else {
            print("⏭️ [HomeView] Skipping load - already in progress")
            return
        }

        guard let baseURL = sessionManager.serverURL else {
            print("❌ [HomeView] No server URL")
            return
        }

        loadingFeed = true
        defer { loadingFeed = false }

        let client = APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { self.sessionManager.deviceToken },
            userTokenProvider: { self.sessionManager.userToken }
        )

        do {
            print("🔄 [HomeView] Loading feed...")
            let feed = try await client.getCurrentFeed()
            print("✅ [HomeView] Feed loaded: \(feed.items.count) items")
            feedData = feed
            feedError = nil
        } catch {
            print("❌ [HomeView] Failed to load feed: \(error)")
            feedData = nil
            feedError = error
        }
    }

    private func refreshFeed() async {
        // Used by pull-to-refresh - refresh both feed and schedule
        async let feedTask: () = loadExistingFeed()
        async let scheduleTask: () = loadFeedSchedule()
        _ = await (feedTask, scheduleTask)
    }

    private func loadFeedSchedule() async {
        guard let baseURL = sessionManager.serverURL else { return }

        let client = APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { self.sessionManager.deviceToken },
            userTokenProvider: { self.sessionManager.userToken }
        )

        do {
            feedSchedule = try await client.getFeedSchedule()
        } catch {
            print("❌ [HomeView] Failed to load feed schedule: \(error)")
        }
    }

    // TEMP: Debug function to manually trigger feed insight generation
    private func generateFeedInsights() async {
        guard let baseURL = sessionManager.serverURL else {
            print("❌ [HomeView] No server URL")
            return
        }

        let client = APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { self.sessionManager.deviceToken },
            userTokenProvider: { self.sessionManager.userToken }
        )

        do {
            print("🧪 [HomeView] Triggering feed insight generation...")
            try await client.triggerFeedInsightGeneration()
            print("✅ [HomeView] Feed insight generation triggered")
            // Feed will auto-refresh via SSE when insights are ready
        } catch {
            print("❌ [HomeView] Failed to trigger generation: \(error)")
        }
    }

    // Time-based greeting
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private var greetingIcon: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "sun.horizon"
        case 12..<17:
            return "sun.max"
        default:
            return "moon.stars"
        }
    }

    @ViewBuilder
    private var welcomeEmptyState: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Greeting header
            HStack(spacing: 12) {
                Image(systemName: greetingIcon)
                    .font(.system(size: 20))
                    .foregroundColor(Color.foreground["000"])

                Text(greeting)
                    .headline()
                    .foregroundColor(Color.foreground["000"])
            }
            .padding(.top, 16)

            // Onboarding card with dashed border
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(Color.foreground["000"])
                        Text("This is Houston, do you copy?")
                            .titleSmall()
                            .foregroundColor(Color.foreground["000"])
                    }

                    Text("Let's get you set up. Start with goals or connecting integrations, in the future you can do either from menu in top right.")
                                .body()
                                .foregroundColor(Color.foreground["200"])
                }


                // Step 1: Create a goal
                HStack(alignment: .top, spacing: 12) {
                    // Numbered circle
                    ZStack {
                        Circle()
                            .stroke(Color.foreground["000"], lineWidth: 0.5)
                            .frame(width: 20, height: 20)
                        Text("1")
                            .bodySmall()
                            .foregroundColor(Color.foreground["000"])
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Houston works great with multiple goals, but let's start by creating the first one.")
                            .body()
                            .foregroundColor(Color.foreground["000"])

                        StandardButton(
                            title: "Start a Goal",
                            variant: .outline,
                            action: {
                                navigationVM.openGoalCreation()
                            }
                        )
                    }
                }

                // Step 2: Connect integrations
                HStack(alignment: .top, spacing: 12) {
                    // Numbered circle
                    ZStack {
                        Circle()
                            .stroke(Color.foreground["000"], lineWidth: 0.5)
                            .frame(width: 20, height: 20)
                        Text("2")
                            .bodySmall()
                            .foregroundColor(Color.foreground["000"])
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connect to integrations with remote MCP or by setting API keys on server and connecting through the app.")
                            .body()
                            .foregroundColor(Color.foreground["000"])

                        StandardButton(
                            title: "Connect Integrations",
                            variant: .outline,
                            action: {
                                showingIntegrations = true
                            }
                        )
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 28)
            .padding(.leading, 20)
            .padding(.trailing, 24)
            .overlay(
                AnimatedGradientBorder(cornerRadius: 20, phase: gradientPhase)
            )
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    gradientPhase = 1
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .sheet(isPresented: $showingIntegrations) {
            NavigationStack {
                MCPIntegrationsView()
                    .navigationTitle("Integrations")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingIntegrations = false
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    func feedContent(_ feed: FeedResponse) -> some View {
        let groupedFeed = feed.groupedByTimePeriod()

        VStack(spacing: 24) {
            if groupedFeed.isEmpty {
                Text("No content yet today. Check back later!")
                    .bodyLarge()
                    .foregroundColor(Color.foreground["300"])
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
            } else {
                // Render grouped sections (evening → afternoon → morning)
                ForEach(Array(groupedFeed.enumerated()), id: \.element.id) { index, group in
                    feedSection(group, index: index, totalSections: groupedFeed.count)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func feedSection(_ group: FeedGroup, index: Int, totalSections: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header with contextual title
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: group.period.icon)
                        .font(.system(size: 12))
                    Text(group.period.displayTitle(isNewest: index == 0, sectionIndex: index, totalSections: totalSections))
                        .body()
                }
                .foregroundColor(Color.foreground["000"])
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.background["100"])
                .clipShape(Capsule())
                Spacer()
            }
            .padding(.top, index == 0 ? 0 : 24)

            // Section items
            VStack(spacing: 20) {
                ForEach(group.items) { item in
                    feedItemView(item)
                }
            }
        }
    }

    @ViewBuilder
    private func feedItemView(_ item: FeedItem) -> some View {
        switch item.data {
        case .note(let noteData):
            // Convert NoteData to Note and use standard NoteCard
            let note = Note(
                id: noteData.id,
                title: noteData.title,
                content: noteData.content,
                source: .agent, // Feed notes are from agents
                createdAt: nil,
                ogImage: nil,
                images: nil,
                goalId: noteData.goalId,
                metadata: nil
            )
            // Get goal and accent color if available
            let goal = noteData.goalId.flatMap { goalId in
                navigationVM.goalsVM.goals.first(where: { $0.id == goalId })
            }
            let accentColor = goal.map { Color.accent($0) } ?? Color.foreground["000"]

            Button {
                navigationVM.openNote(id: noteData.id)
            } label: {
                NoteCard(note: note, accentColor: accentColor, goal: goal)
            }
            .buttonStyle(.plain)
        case .discovery(let discoveryData):
            DiscoveryCard(discovery: discoveryData)
        case .reflection(let reflectionData):
            // Get the first goal from reflection's goal_ids
            let goal = reflectionData.goalIds?.first.flatMap { goalId in
                navigationVM.goalsVM.goals.first(where: { $0.id == goalId })
            }
            let reflectionSourceID = "noteComposeReflection-\(item.id)"
            ReflectionCard(reflection: reflectionData, goal: goal, noteTransition: noteTransition, sourceID: reflectionSourceID) {
                navigationVM.openNoteCompose(goal: goal, sourceID: reflectionSourceID)
            }
        }
    }
}

// Helper for sheet binding with note ID
struct NoteIdentifier: Identifiable, Equatable {
    let id: String
}
