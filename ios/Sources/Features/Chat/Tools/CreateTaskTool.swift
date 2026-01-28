import Foundation
import SwiftUI

// MARK: - Create Task Tool (Data + UI)

struct CreateTaskTool: ToolHandler {
    static let toolName = "create_task"

    let id: String
    var status: ToolStatus
    var taskId: String?
    var taskTitle: String?
    var taskStatus: String?
    var displayMessage: String?  // From backend - handles all priority logic

    var displayTitle: String {
        return taskTitle ?? "Create Task"
    }

    var isUserFacing: Bool { true }
    
    init?(id: String, metadata: [String: Any]) {
        self.id = id

        // Extract standardized tool_activity structure
        guard let activity = ToolActivityExtractor(metadata: metadata) else {
            return nil
        }

        self.status = activity.status
        self.taskId = activity.data.stringOrInt(for: "task_id")
        self.taskTitle = activity.data.string(for: "task_title")
        self.taskStatus = activity.data.string(for: "task_status")
        self.displayMessage = activity.displayMessage
    }

    mutating func update(from metadata: [String: Any]) {
        guard let activity = ToolActivityExtractor(metadata: metadata) else {
            return
        }

        self.status = activity.status
        // Note: Other fields are immutable (let), so we only update status
        // Updated task data will come through a fresh message from backend
    }
    
    func createView(actions: ChatCellActions) -> AnyView {
        AnyView(CreateTaskCell(tool: self, actions: actions))
    }
}

// MARK: - Create Task Cell

private struct CreateTaskCell: View {
    let tool: CreateTaskTool
    let actions: ChatCellActions

    private var isActive: Bool {
        tool.taskStatus == "active" || tool.taskStatus == nil
    }
    
    private var activityColor: Color {
        // Use goal accent color if available and task is not completed
        if isActive {
            return Color.accent(actions.goal)
        }
        return Color.foreground["300"]
    }
    
    var body: some View {
        Button {
            if let taskId = tool.taskId {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                actions.onOpenTask(taskId)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.foreground["300"])

                HStack(spacing: 8) {
                    Text(activityMessage)
                        .body()
                        .foregroundStyle(Color.foreground["100"])
                        .shimmer(
                            isActive: isActive,
                        )
                    
                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.foreground["300"])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .shimmerBorder(
                isActive: isActive,
                baseColor: Color.foreground["200"].opacity(0.2),
                accentColor: activityColor,
                lineWidth: 1,
                cornerRadius: 14,
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    /// Display message - backend handles all priority logic
    private var activityMessage: String {
        // 1. Completed → show title
        if tool.taskStatus == "completed" {
            return tool.taskTitle ?? "Task completed"
        }
        
        // 2. Display message from backend
        if let displayMessage = tool.displayMessage {
            return displayMessage
        }
        
        // 3. Task title
        if let title = tool.taskTitle {
            return title
        }
        
        // 4. Fallback
        return "Spinning up task"
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
