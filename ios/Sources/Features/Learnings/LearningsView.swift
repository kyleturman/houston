import SwiftUI

/// Context for learnings - either a goal or the user agent
enum LearningsContext {
    case goal(Goal)
    case userAgent

    var descriptionText: String {
        switch self {
        case .goal:
            return "Insights and context the agent has learned while working on this goal."
        case .userAgent:
            return "Insights and context Houston has learned about you across all your goals."
        }
    }

    var emptyStateText: String {
        switch self {
        case .goal:
            return "As you work on this goal, the agent will learn and remember important context about your preferences and progress."
        case .userAgent:
            return "As you interact with Houston, it will learn and remember important context about your preferences."
        }
    }
}

struct LearningsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionManager.self) var session
    @State private var goal: Goal?
    @State private var learnings: [[String: String]] = []
    @State private var showingInputSheet = false
    @State private var editingIndex: Int? = nil
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var learningToDelete: Int? = nil
    @State private var showingDeleteConfirmation = false

    private let context: LearningsContext

    /// Accent color computed inside view for MainActor context
    private var accentColor: Color {
        switch context {
        case .goal(let goal):
            return Color.accent(goal)
        case .userAgent:
            return Color.accent(nil)
        }
    }

    /// Initialize for a goal
    init(goal: Goal) {
        self.context = .goal(goal)
        self._goal = State(initialValue: goal)
        self._learnings = State(initialValue: goal.learnings ?? [])
    }

    /// Initialize for user agent
    init(isUserAgent: Bool = true) {
        self.context = .userAgent
        self._goal = State(initialValue: nil)
        self._learnings = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && learnings.isEmpty {
                    ProgressView("Loading...")
                } else if learnings.isEmpty {
                    ContentUnavailableView(
                        "No Learnings",
                        systemImage: "lightbulb",
                        description: Text(context.emptyStateText)
                    )
                } else {
                    learningsList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 14))
                        Text("Learnings")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingIndex = nil
                        inputText = ""
                        showingInputSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadLearningsIfNeeded()
            }
            .presentationDragIndicator(.visible)
            .sheet(isPresented: $showingInputSheet) {
                LearningInputSheet(
                    title: editingIndex == nil ? "Add Learning" : "Edit Learning",
                    text: $inputText,
                    accentColor: accentColor,
                    onSave: {
                        Task {
                            await saveLearning()
                        }
                    }
                )
                .presentationDetents([.height(200)])
            }
            .alert("Delete Learning", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    learningToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let index = learningToDelete {
                        deleteLearning(at: index)
                    }
                    learningToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this learning?")
            }
        }
    }

    @ViewBuilder
    private var learningsList: some View {
        List {
            Text(context.descriptionText)
                .body()
                .foregroundColor(Color.foreground["500"])
                .listRowSeparator(.hidden)
                .padding(.top, -8)
                .padding(.trailing, -8)
                .padding(.bottom, -12)

            ForEach(Array((sortedLearnings).enumerated()), id: \.offset) { index, learning in
                LearningRow(learning: learning)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                learningToDelete = originalIndex(for: index)
                                showingDeleteConfirmation = true
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            editLearning(at: originalIndex(for: index))
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(accentColor)
                    }
            }
        }
        .listStyle(.plain)
    }

    /// Sort learnings by timestamp, most recent first
    private var sortedLearnings: [(index: Int, learning: [String: String])] {
        let indexed = learnings.enumerated().map { (index: $0.offset, learning: $0.element) }

        return indexed.sorted { a, b in
            let dateA = parseDate(from: a.learning)
            let dateB = parseDate(from: b.learning)

            // Most recent first
            if let dateA = dateA, let dateB = dateB {
                return dateA > dateB
            } else if dateA != nil {
                return true
            } else if dateB != nil {
                return false
            }
            return a.index > b.index // Fallback: higher index = more recent
        }
    }

    /// Get the original index in learnings for a sorted index
    private func originalIndex(for sortedIndex: Int) -> Int {
        sortedLearnings[sortedIndex].index
    }

    private func parseDate(from learning: [String: String]) -> Date? {
        // Prefer updated_at over created_at for sorting (most recently modified first)
        guard let timestamp = learning["updated_at"] ?? learning["timestamp"] ?? learning["created_at"] else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: timestamp)
    }

    private func loadLearningsIfNeeded() async {
        // For goals, learnings are already loaded from the goal object
        // For user agent, we need to fetch from the API
        guard case .userAgent = context else { return }

        isLoading = true
        defer { isLoading = false }

        guard let client = makeAPIClient() else {
            print("Failed to create API client")
            return
        }

        do {
            let userAgent = try await client.getUserAgent()
            await MainActor.run {
                learnings = userAgent.attributes.learnings ?? []
            }
        } catch {
            print("❌ [LearningsView] Failed to load user agent learnings: \(error)")
        }
    }

    private func editLearning(at index: Int) {
        guard index < learnings.count else { return }
        let learning = learnings[index]
        editingIndex = index
        inputText = learning["content"] ?? learning["text"] ?? learning["learning"] ?? ""
        showingInputSheet = true
    }

    private func deleteLearning(at index: Int) {
        Task {
            isLoading = true

            guard let client = makeAPIClient() else {
                print("Failed to create API client")
                isLoading = false
                return
            }

            var updatedLearnings = learnings
            updatedLearnings.remove(at: index)
            let learningStrings = updatedLearnings.compactMap { $0["content"] ?? $0["text"] ?? $0["learning"] }

            do {
                switch context {
                case .goal(let goal):
                    let updatedGoal = try await client.updateGoal(
                        id: goal.id,
                        learnings: learningStrings
                    )
                    await MainActor.run {
                        self.goal = Goal.from(resource: updatedGoal)
                        self.learnings = self.goal?.learnings ?? []
                        isLoading = false
                    }
                case .userAgent:
                    let updatedUserAgent = try await client.updateUserAgent(learnings: learningStrings)
                    await MainActor.run {
                        self.learnings = updatedUserAgent.attributes.learnings ?? []
                        isLoading = false
                    }
                }
            } catch {
                print("Failed to delete learning: \(error)")
                isLoading = false
            }
        }
    }

    private func saveLearning() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showingInputSheet = false
            return
        }

        await MainActor.run { isLoading = true }

        guard let client = makeAPIClient() else {
            print("Failed to create API client")
            await MainActor.run { isLoading = false }
            return
        }

        var updatedLearnings = learnings

        if let editIndex = editingIndex {
            // Edit existing learning
            if editIndex < updatedLearnings.count {
                updatedLearnings[editIndex]["content"] = inputText
            }
        } else {
            // Add new learning
            updatedLearnings.append(["content": inputText])
        }

        let learningStrings = updatedLearnings.compactMap { $0["content"] ?? $0["text"] ?? $0["learning"] }

        do {
            switch context {
            case .goal(let goal):
                let updatedGoal = try await client.updateGoal(
                    id: goal.id,
                    learnings: learningStrings
                )
                await MainActor.run {
                    self.goal = Goal.from(resource: updatedGoal)
                    self.learnings = self.goal?.learnings ?? []
                    showingInputSheet = false
                    inputText = ""
                    editingIndex = nil
                    isLoading = false
                }
            case .userAgent:
                let updatedUserAgent = try await client.updateUserAgent(learnings: learningStrings)
                await MainActor.run {
                    self.learnings = updatedUserAgent.attributes.learnings ?? []
                    showingInputSheet = false
                    inputText = ""
                    editingIndex = nil
                    isLoading = false
                }
            }
        } catch {
            print("Failed to save learning: \(error)")
            await MainActor.run { isLoading = false }
        }
    }

    private func makeAPIClient() -> APIClient? {
        guard let baseURL = session.serverURL else { return nil }
        return APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { session.deviceToken },
            userTokenProvider: { session.userToken }
        )
    }
}

// MARK: - Learning Row

private struct LearningRow: View {
    let learning: (index: Int, learning: [String: String])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Content
            if let content = learning.learning["content"] ?? learning.learning["text"] ?? learning.learning["learning"] {
                Text(content)
                    .body()
            }

            // Date - prefer updated_at to show when learning was last modified
            if let timestamp = learning.learning["updated_at"] ?? learning.learning["timestamp"] ?? learning.learning["created_at"] {
                Text(formatTimestamp(timestamp))
                    .caption()
                    .foregroundStyle(Color.foreground["500"])
            }
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
        .alignmentGuide(VerticalAlignment.center) { d in d[.top] + 12 }
    }

    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: timestamp) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy"
            return dateFormatter.string(from: date)
        }
        return timestamp
    }
}

// MARK: - Learning Input Sheet

struct LearningInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var text: String
    let accentColor: Color
    let onSave: () -> Void
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Text input with transparent background
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Enter learning...")
                            .body()
                            .foregroundColor(Color.foreground["300"])
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $text)
                        .font(.system(size: 16))
                        .foregroundColor(Color.foreground["000"])
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .focused($isInputFocused)
                }
                .frame(minHeight: 100)

                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Goal - With Learnings") {
    LearningsView(
        goal: Goal(
            id: "1",
            title: "Fitness Goal",
            description: "Get healthier",
            status: .working,
            accentColor: "blue",
            learnings: [
                ["content": "User prefers morning workouts between 6-7am", "timestamp": "2024-01-15T08:30:00Z"],
                ["content": "Completed 5 consecutive days of meditation practice", "timestamp": "2024-01-14T19:00:00Z"],
                ["content": "User has a standing meeting every Tuesday at 2pm", "timestamp": "2024-01-13T10:00:00Z"]
            ]
        )
    )
}

#Preview("Goal - Empty State") {
    LearningsView(
        goal: Goal(
            id: "1",
            title: "New Goal",
            description: "Just started",
            status: .waiting,
            accentColor: "green",
            learnings: []
        )
    )
}

#Preview("User Agent") {
    LearningsView(isUserAgent: true)
}
