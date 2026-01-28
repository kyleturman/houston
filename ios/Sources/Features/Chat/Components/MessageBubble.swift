import SwiftUI

/// Reusable message bubble component for chat interfaces
/// Displays messages with source-based styling (user vs agent vs system)
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.source == .user {
                HStack {
                    MarkdownText(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.foreground["000"].opacity(0.05))
                        .foregroundColor(Color.foreground["000"])
                        .cornerRadius(14)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.top, 16)
                .padding(.leading, 16)
            }
            if message.source == .agent {
                // Always use StreamingText for consistent rendering
                // It handles both streaming (animated) and static (immediate) display
                StreamingText(content: message.content, isStreaming: message.isStreaming)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 2)
                    .padding(.trailing, 4)
            }
            if message.source == .error {
                MarkdownText(message.content)
                    .padding(12)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(Color.foreground["000"])
                    .cornerRadius(16)
            }
        }
    }
}
