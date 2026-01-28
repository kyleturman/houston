import SwiftUI

struct ActivityView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(StateManager.self) private var stateManager
    @Environment(NavigationViewModel.self) var navigationVM
    @State private var viewModel: ActivityViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel?.loading ?? true {
                    ProgressView()
                        .padding()
                } else if let errorMessage = viewModel?.errorMessage {
                    VStack(spacing: 12) {
                        Text("Error loading activities")
                            .font(.headline)
                            .foregroundColor(Color.foreground["000"])

                        Text(errorMessage)
                            .font(.body)
                            .foregroundColor(Color.foreground["300"])
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if viewModel?.activities.isEmpty ?? true {
                    VStack(spacing: 12) {
                        Text("No activity yet")
                            .font(.headline)
                            .foregroundColor(Color.foreground["000"])

                        Text("Agent execution history will appear here")
                            .font(.body)
                            .foregroundColor(Color.foreground["300"])
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel?.activities ?? []) { activity in
                            ActivityCard(activity: activity)
                                .onAppear {
                                    // Load more when approaching end of list
                                    if shouldLoadMore(for: activity) {
                                        Task {
                                            await viewModel?.loadMore()
                                        }
                                    }
                                }
                        }

                        if viewModel?.loadingMore ?? false {
                            ProgressView()
                                .padding()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color.background["000"])
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel?.refresh()
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ActivityViewModel(session: sessionManager)
                Task {
                    await viewModel?.load()
                }
            }
        }
        .onReceive(stateManager.dataRefreshNeededPublisher) { _ in
            // Refresh activity when app returns from background
            Task { await viewModel?.load() }
        }
    }

    /// Determine if we should load more items
    private func shouldLoadMore(for activity: AgentActivityItem) -> Bool {
        guard let viewModel = viewModel else { return false }
        guard !viewModel.activities.isEmpty else { return false }

        // Load more when we're 5 items from the end
        let threshold = max(1, viewModel.activities.count - 5)
        if let index = viewModel.activities.firstIndex(where: { $0.id == activity.id }),
           index >= threshold {
            return true
        }

        return false
    }
}

// MARK: - Activity Card

struct ActivityCard: View {
    let activity: AgentActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon, type, and timestamp
            HStack {
                Image(systemName: activity.icon)
                    .font(.system(size: 17))
                    .foregroundColor(Color.foreground["000"])
                    .padding(.leading, -1)

                Text(activity.agentTypeLabel)
                    .bodyLarge()
                    .foregroundColor(Color.foreground["000"])

                Spacer()

                Text(activity.relativeTimeAgo)
                    .caption()
                    .foregroundColor(Color.foreground["300"])
            }

            // Metrics row
            HStack(spacing: 16) {
                // Iterations
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color.foreground["300"])
                    Text("\(activity.iterations)")
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                }

                // Tokens
                HStack(spacing: 4) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 12))
                        .foregroundColor(Color.foreground["300"])
                    Text("\(formatNumber(activity.totalTokens))")
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                }

                // Cost
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 12))
                        .foregroundColor(Color.foreground["300"])
                    Text(activity.formattedCost)
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                }

                // Duration
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(Color.foreground["300"])
                    Text(activity.formattedDuration)
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                }
            }

            if (!activity.naturalCompletion) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundColor(Color.semantic["warning"])
                    Text("Max iterations hit")
                        .caption()
                        .foregroundColor(Color.semantic["warning"])
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.background["100"])
        .cornerRadius(12)
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            return String(format: "%.1fk", Double(number) / 1000)
        }
        return "\(number)"
    }
}

#Preview {
    NavigationStack {
        ActivityView()
    }
}
