import Foundation
import SwiftUI

// MARK: - Create Note Tool (Data + UI)

struct CreateNoteTool: ToolHandler {
    static let toolName = "create_note"
    var displayTitle: String { "Note" }

    let id: String
    var status: ToolStatus
    let noteId: String?
    let noteTitle: String?
    let noteContent: String?
    let notePreview: String?
    let progressMessage: String?

    var isUserFacing: Bool { true }
    
    init?(id: String, metadata: [String: Any]) {
        self.id = id

        // Extract from tool_activity (standardized backend structure)
        let toolActivity = metadata.dictionary(for: "tool_activity")
        self.status = ToolStatus(from: toolActivity?.string(for: "status") ?? "in_progress")

        // All tool data is in tool_activity.data (standardized)
        let noteData = toolActivity?.dictionary(for: "data")
        self.noteId = noteData?.stringOrInt(for: "note_id")
        self.noteTitle = noteData?.string(for: "title")
        self.noteContent = noteData?.string(for: "content")
        self.notePreview = noteData?.string(for: "preview")
        self.progressMessage = toolActivity?.string(for: "display_message")
    }
    
    mutating func update(from metadata: [String: Any]) {
        let toolActivity = metadata.dictionary(for: "tool_activity")

        if let newStatus = toolActivity?.string(for: "status") {
            self.status = ToolStatus(from: newStatus)
        }
        // Note: Other fields are immutable (let), so we only update status
        // Updated content/title will come through a fresh message from backend
    }
    
    func createView(actions: ChatCellActions) -> AnyView {
        AnyView(CreateNoteCell(tool: self, actions: actions))
    }
}

// MARK: - Create Note Cell

private struct CreateNoteCell: View {
    let tool: CreateNoteTool
    let actions: ChatCellActions
    
    private var statusText: String {
        switch tool.status {
        case .inProgress:
            return "Writing note"
        case .success:
            return "Added a note"
        case .failure:
            return "Failed to create note"
        }
    }
    
    private var content: String {
        let rawContent: String
        if let noteContent = tool.noteContent, !noteContent.isEmpty {
            rawContent = noteContent
        } else if let preview = tool.notePreview, !preview.isEmpty {
            rawContent = preview
        } else if let progress = tool.progressMessage, !progress.isEmpty {
            rawContent = progress
        } else {
            return "Creating note..."
        }
        
        // Strip markdown formatting and newlines for clean preview
        return MarkdownUtils.toPlainText(rawContent)
    }
    
    var body: some View {
        Button {
            if let noteId = tool.noteId {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                actions.onOpenNote(noteId)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.foreground["300"])

                    Text(statusText)
                        .body()
                        .foregroundStyle(Color.foreground["300"])
                }

                if (tool.noteTitle != nil && tool.noteContent != nil) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tool.noteTitle ?? "")
                            .body()
                            .foregroundStyle(Color.foreground["100"])
                            .lineLimit(2)
                            .truncationMode(.tail)
                    
                        Text(content)
                            .bodySmall()
                            .foregroundStyle(Color.foreground["400"])
                            .lineLimit(5)
                            .truncationMode(.tail)
                    }
                    .padding(.leading, 10)
                    .padding(.bottom, 4)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.foreground["500"])
                            .frame(width: 1)
                            .padding(.leading, 2)
                    }
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.6),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.foreground["200"].opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
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
