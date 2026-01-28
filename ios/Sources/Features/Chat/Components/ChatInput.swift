import SwiftUI

struct ChatInput: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @State private var sendButtonScale: CGFloat = 1.0
    @State private var bounceScale: CGFloat = 1.0

    let placeholder: String
    let isExpanded: Bool
    let shouldFocusOnAppear: Bool
    let onSend: () -> Void
    let isSendDisabled: Bool

    init(text: Binding<String>,
         isFocused: FocusState<Bool>.Binding,
         placeholder: String = "What can I help you with?",
         isExpanded: Bool,
         shouldFocusOnAppear: Bool = false,
         onSend: @escaping () -> Void,
         isSendDisabled: Bool = false) {
        self._text = text
        self._isFocused = isFocused
        self.placeholder = placeholder
        self.isExpanded = isExpanded
        self.shouldFocusOnAppear = shouldFocusOnAppear
        self.onSend = onSend
        self.isSendDisabled = isSendDisabled
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color.foreground["500"]), axis: .vertical)
                .font(.bodyLarge)
                .tracking(-0.1)
                .foregroundColor(Color.foreground["000"])
                .focused($isFocused)
                .lineLimit(1...5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .padding(.vertical, 12)
                // .fixedSize(horizontal: false, vertical: true)
                .onSubmit {
                    onSend()
                }
                .onAppear {
                    if shouldFocusOnAppear {
                        // Small delay for smooth sheet presentation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            isFocused = true
                        }
                    }
                }
                .onChange(of: isFocused) { oldValue, newValue in
                    // Trigger bounce when focusing (from unfocused to focused)
                    if !oldValue && newValue {
                        bounceScale = 0.95
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                            bounceScale = 1.0
                        }
                    }
                }

            sendButton
                .padding(.bottom, 8)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .scaleEffect(bounceScale)
        .glassBackground(cornerRadius: 24, fill: Color.background["300"].opacity(0.5))
        .onTapGesture {
            if !isFocused {
                isFocused = true
            }
        }
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .foregroundColor(Color.background["000"])
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color.foreground["000"])
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendDisabled)
        .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendDisabled ? 0.5 : 1.0)
        .opacity(isExpanded ? 1.0 : 0.0)
        .animation(.easeOut(duration: isExpanded ? 0.25 : 0.1), value: isExpanded)
        .scaleEffect(sendButtonScale, anchor: .center)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                // Scale from 0.1 to 1.0 when expanding
                sendButtonScale = 0.7
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.15)) {
                    sendButtonScale = 1.0
                }
            } else {
                // No scale animation when collapsing, just keep at 1.0
                sendButtonScale = 1.0
            }
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @FocusState var isFocused: Bool
    
    return ChatInput(
        text: $text, 
        isFocused: $isFocused,
        isExpanded: isFocused
    ) {
        print("Send: \(text)")
        text = ""
        isFocused = false
    }
    .background(Color.background["100"])
}
