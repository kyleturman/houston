import SwiftUI
import UIKit
import SwiftUINavigationTransitions

/// Clean, minimal footer action bar using reusable components
struct FooterActionBar: View {
    @Environment(NavigationViewModel.self) var navigationVM
    @FocusState private var isInputFocused: Bool
    @State private var inputText = ""
    @Binding var showChatSheet: Bool
    @Binding var showNoteComposeSheet: Bool
    @Binding var footerMinY: CGFloat // Track position for FooterChatSheet

    let currentGoal: Goal?
    let chatViewModel: ChatViewModel? // Context-aware: goal or user agent
    let noteTransition: Namespace.ID

    init(currentGoal: Goal? = nil, showChatSheet: Binding<Bool> = .constant(false), showNoteComposeSheet: Binding<Bool> = .constant(false), footerMinY: Binding<CGFloat> = .constant(0), chatViewModel: ChatViewModel? = nil, noteTransition: Namespace.ID) {
        self.currentGoal = currentGoal
        self._showChatSheet = showChatSheet
        self._showNoteComposeSheet = showNoteComposeSheet
        self._footerMinY = footerMinY
        self.chatViewModel = chatViewModel
        self.noteTransition = noteTransition
    }
    
    private var isExpanded: Bool {
        showChatSheet
    }
    
    private var placeholder: String {
        if let goal = currentGoal {
            return "Ask about \(goal.title)..."
        } else {
            return "What can I help you with?"
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: isExpanded ? 0 : 12) {
            ChatInput(
                text: $inputText,
                isFocused: $isInputFocused,
                placeholder: placeholder,
                isExpanded: isExpanded,
                onSend: sendMessage
            )
            .animation(.spring(response: 0.3, dampingFraction: 1), value: isExpanded)
            
            ZStack {
                plusButton
            }
            .frame(width: isExpanded ? 0 : 44)
        }
        .overlay(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        footerMinY = geometry.frame(in: .global).minY
                    }
                    .onChange(of: geometry.frame(in: .global).minY) { _, newValue in
                        footerMinY = newValue
                    }
            }
        )
        .onChange(of: isInputFocused) { _, focused in
            if focused {
                showChatSheet = true
            }
        }
        .onChange(of: showChatSheet) { _, isShowing in
            if !isShowing {
                // Blur input immediately when sheet starts closing
                isInputFocused = false
            }
        }
        .onAppear {
            // Sync input text with ChatViewModel if available
            if let chatViewModel = chatViewModel {
                inputText = chatViewModel.input
            }
        }
        .onChange(of: inputText) { _, newText in
            // Keep ChatViewModel input in sync
            chatViewModel?.input = newText
        }
        .padding(.horizontal, isExpanded ? 8 : 14)
        .padding(.bottom, isInputFocused ? 6 : 24)
        .safeAreaPadding(.bottom, isInputFocused ? 0 : nil)
        .animation(.easeOut(duration: isInputFocused ? 0.15 : 0.25), value: isInputFocused)
    }
    
    private var plusButton: some View {
        IconButton(
            iconName: "plus",
            backgroundColor: Color.accent(currentGoal),
            action: {
                navigationVM.noteComposeSourceID = "noteComposeFooter"
                showNoteComposeSheet = true
            }
        )
        .matchedTransitionSource(id: "noteComposeFooter", in: noteTransition)
        .opacity(isExpanded ? 0 : 1)
        .animation(.easeOut(duration: isExpanded ? 0 : 0.25), value: isExpanded)
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let chatViewModel = chatViewModel {
            // Ensure ChatViewModel has the latest input text before sending
            chatViewModel.input = inputText
            Task {
                await chatViewModel.send()
                await MainActor.run {
                    inputText = ""
                }
            }
        } else {
            // No chat view model available - just clear input
            inputText = ""
        }
    }
}

#Preview {
    @Previewable @Namespace var noteTransition

    VStack {
        FooterActionBar(noteTransition: noteTransition)

        FooterActionBar(currentGoal: Goal(id: "1", title: "Learn Swift", description: "Master iOS development", status: .working, createdAt: Date(), updatedAt: Date()), noteTransition: noteTransition)
    }
    .background(Color.background["100"])
    .environment(NavigationViewModel(goalsViewModel: GoalsViewModel(session: SessionManager())))
}

