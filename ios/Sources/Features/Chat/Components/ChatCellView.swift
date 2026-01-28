import SwiftUI

/// Universal chat cell view that renders the appropriate cell type based on message content
struct ChatCellView: View {
    let message: ChatMessage
    let actions: ChatCellActions
    let isTaskContext: (String) -> Bool

    @State private var isVisible = false

    var body: some View {
        Group {
            // Tool cells - clean routing through the new modular system
            // Only user-facing tools create ThreadMessages (backend enforces this)
            if let tool = message.tool {
                tool.createView(actions: actions)
            }
            // No special cell needed - will show as regular text message
        }
        .opacity(isVisible ? 1 : 0)
        .frame(height: isVisible ? nil : 0, alignment: .top)
        .clipped()
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                isVisible = true
            }
        }
    }
}
