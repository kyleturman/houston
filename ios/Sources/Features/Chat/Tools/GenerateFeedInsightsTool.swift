import Foundation
import SwiftUI

// MARK: - Generate Feed Insights Tool (Data + UI)

struct GenerateFeedInsightsTool: ToolHandler {
    static let toolName = "generate_feed_insights"
    var displayTitle: String { "Feed Insights" }

    let id: String
    var status: ToolStatus
    let reflectionCount: Int
    let discoveryCount: Int
    let progressMessage: String?

    var isUserFacing: Bool { true }

    init?(id: String, metadata: [String: Any]) {
        self.id = id

        // Extract from tool_activity (standardized backend structure)
        let toolActivity = metadata.dictionary(for: "tool_activity")
        self.status = ToolStatus(from: toolActivity?.string(for: "status") ?? "in_progress")
        self.progressMessage = toolActivity?.string(for: "display_message")

        // All tool data is in tool_activity.data (standardized)
        let toolData = toolActivity?.dictionary(for: "data")
        self.reflectionCount = toolData?.int(for: "reflection_count") ?? 0
        self.discoveryCount = toolData?.int(for: "discovery_count") ?? 0
    }

    mutating func update(from metadata: [String: Any]) {
        let toolActivity = metadata.dictionary(for: "tool_activity")
        if let newStatus = toolActivity?.string(for: "status") {
            self.status = ToolStatus(from: newStatus)
        }
    }

    func createView(actions: ChatCellActions) -> AnyView {
        AnyView(GenerateFeedInsightsCell(tool: self))
    }
}

// MARK: - Generate Feed Insights Cell

private struct GenerateFeedInsightsCell: View {
    let tool: GenerateFeedInsightsTool

    private var statusText: String {
        switch tool.status {
        case .inProgress:
            return tool.progressMessage ?? "Generating insights..."
        case .success:
            return "Generated insights"
        case .failure:
            return "Failed to generate insights"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.foreground["300"])

                Text(statusText)
                    .body()
                    .foregroundStyle(Color.foreground["300"])

                Spacer()

                statusView
            }

            // Show counts when completed
            if tool.status == .success && (tool.reflectionCount > 0 || tool.discoveryCount > 0) {
                HStack(spacing: 16) {
                    if tool.reflectionCount > 0 {
                        Label {
                            Text("\(tool.reflectionCount) reflection\(tool.reflectionCount == 1 ? "" : "s")")
                                .bodySmall()
                                .foregroundStyle(Color.foreground["300"])
                        } icon: {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.foreground["400"])
                        }
                    }

                    if tool.discoveryCount > 0 {
                        Label {
                            Text("\(tool.discoveryCount) discover\(tool.discoveryCount == 1 ? "y" : "ies")")
                                .bodySmall()
                                .foregroundStyle(Color.foreground["300"])
                        } icon: {
                            Image(systemName: "link")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.foreground["400"])
                        }
                    }
                }
                .padding(.leading, 23)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch tool.status {
        case .inProgress:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color.foreground["000"]))
        case .success:
            EmptyView()
        case .failure:
            Text("Failed")
                .captionSmall()
                .foregroundStyle(Color.semantic["error"])
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.semantic["error"].opacity(0.1))
                .clipShape(Capsule())
        }
    }
}
