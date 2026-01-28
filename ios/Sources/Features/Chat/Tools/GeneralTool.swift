import Foundation
import SwiftUI

// MARK: - General Tool (Fallback Data + UI)

struct GeneralTool: ToolHandler {
    static let toolName = "general" // This is a fallback, not registered directly
    
    let id: String
    var status: ToolStatus
    let actualToolName: String
    let title: String?
    
    var displayTitle: String {
        return title ?? actualToolName.capitalized.replacingOccurrences(of: "_", with: " ")
    }

    // All tools that create ThreadMessages are user-facing (backend enforces this)
    var isUserFacing: Bool { true }

    init?(id: String, metadata: [String: Any]) {
        self.id = id

        // Extract from tool_activity (standardized backend structure)
        let toolActivity = metadata.dictionary(for: "tool_activity")
        self.status = ToolStatus(from: toolActivity?.string(for: "status") ?? "in_progress")
        self.actualToolName = toolActivity?.string(for: "name") ?? "unknown"

        // All tool data is in tool_activity.data (standardized)
        let toolData = toolActivity?.dictionary(for: "data")
        self.title = toolData?.string(for: "title")
    }

    mutating func update(from metadata: [String: Any]) {
        let toolActivity = metadata.dictionary(for: "tool_activity")
        if let newStatus = toolActivity?.string(for: "status") {
            self.status = ToolStatus(from: newStatus)
        }
    }
    
    func createView(actions: ChatCellActions) -> AnyView {
        AnyView(GeneralToolCell(tool: self, actions: actions))
    }
    
    // MARK: - Factory Method

    /// Create general tool as fallback for unknown tools
    static func createFallback(id: String, toolName: String, metadata: [String: Any]) -> GeneralTool {
        var mutableMetadata = metadata
        // Ensure tool_activity exists with the tool name
        if var toolActivity = mutableMetadata["tool_activity"] as? [String: Any] {
            toolActivity["name"] = toolName
            mutableMetadata["tool_activity"] = toolActivity
        } else {
            mutableMetadata["tool_activity"] = ["name": toolName, "status": "in_progress"]
        }
        return GeneralTool(id: id, metadata: mutableMetadata)!
    }
}

// MARK: - General Tool Cell

private struct GeneralToolCell: View {
    let tool: GeneralTool
    let actions: ChatCellActions
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: toolIcon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.foreground["300"])
                
                Text(tool.displayTitle)
                    .body()
                    .foregroundStyle(Color.foreground["300"])
                
                Spacer()
                statusView
            }
        }
        .padding(.vertical, 4)
    }
    
    private var toolIcon: String {
        switch tool.actualToolName {
        case let name where name.contains("search"):
            return "magnifyingglass"
        case let name where name.contains("check_in"):
            return "timer"
        default:
            return "wrench.adjustable"
        }
    }
    
    @ViewBuilder
    private var statusView: some View {
        if tool.status == .inProgress {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color.foreground["000"]))
        } else if case .failure = tool.status {
            Text("Failed")
                .caption().fontWeight(.medium)
                .foregroundStyle(Color.semantic["error"])
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.semantic["error"].opacity(0.1))
                .clipShape(Capsule())
        }
    }
}
