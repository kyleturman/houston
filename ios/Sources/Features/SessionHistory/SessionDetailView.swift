import SwiftUI

struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let session: AgentHistory
    let goalId: String?
    let isUserAgent: Bool
    let client: APIClient

    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && messages.isEmpty {
                ProgressView("Loading messages...")
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("This session has no messages")
                )
            } else {
                messageList
            }
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .task {
            await loadMessages()
        }
        .alert("Delete Session", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await deleteSession()
                }
            }
        } message: {
            Text("Are you sure you want to delete this session? This will also delete all \(messages.count) message(s).")
        }
        .alert("Error", isPresented: Binding.constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                // Session info header
                sessionInfoHeader

                // Messages
                ForEach(messages) { message in
                    MessageBubble(message: message)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var sessionInfoHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.summary)
                .font(.headline)

            HStack(spacing: 16) {
                Label("\(session.messageCount) messages", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(session.tokenCount) tokens", systemImage: "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(session.sessionDateString)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let reason = session.completionReason {
                Text("Reason: \(reason)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .padding(.bottom, 12)
    }

    // MARK: - Actions

    private func loadMessages() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let (_, threadMessages): (AgentHistoryResource, [ThreadMessageResource])

            if isUserAgent {
                (_, threadMessages) = try await client.getUserAgentHistory(historyId: session.id)
            } else if let goalId = goalId {
                (_, threadMessages) = try await client.getGoalAgentHistory(goalId: goalId, historyId: session.id)
            } else {
                throw SessionDetailError.invalidContext
            }

            messages = threadMessages.map { ChatMessage(from: $0) }
        } catch {
            print("❌ [SessionDetailView] Failed to load messages: \(error)")
            errorMessage = "Failed to load session messages"
        }
    }

    private func deleteSession() async {
        do {
            if isUserAgent {
                try await client.deleteUserAgentHistory(historyId: session.id)
            } else if let goalId = goalId {
                try await client.deleteGoalAgentHistory(goalId: goalId, historyId: session.id)
            } else {
                throw SessionDetailError.invalidContext
            }

            dismiss()
        } catch {
            print("❌ [SessionDetailView] Failed to delete session: \(error)")
            errorMessage = "Failed to delete session"
        }
    }

    enum SessionDetailError: Error {
        case invalidContext
    }
}
