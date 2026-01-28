import SwiftUI
import UIKit

/// A utility that triggers the keyboard to appear immediately when a view loads,
/// synchronized with the view's animation (e.g., sheet presentation).
///
/// **Why this is needed:**
/// By default in SwiftUI, when you present a sheet and focus a TextField, the sheet
/// animates in first, then the keyboard appears with a noticeable delay. This creates
/// a two-step animation that feels jarring.
///
/// **How it works:**
/// This utility uses a hidden UITextField that calls `becomeFirstResponder()` immediately
/// when initialized. This triggers the keyboard at the UIKit level before SwiftUI's
/// animation completes, allowing the sheet and keyboard to animate in together smoothly.
///
/// **Usage:**
/// Apply the `.immediateKeyboard()` modifier to your view content, typically inside a sheet:
///
/// ```swift
/// struct MySheet: View {
///     @FocusState private var isFocused: Bool
///     @State private var text = ""
///
///     var body: some View {
///         VStack {
///             TextField("Enter text", text: $text)
///                 .focused($isFocused)
///         }
///         .immediateKeyboard()
///         .onAppear {
///             isFocused = true
///         }
///     }
/// }
/// ```

// MARK: - Hidden UITextField Implementation
private class ImmediateKeyboardTriggerField: UITextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Immediately become first responder to trigger keyboard
        becomeFirstResponder()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ImmediateKeyboardTriggerView: UIViewRepresentable {
    func makeUIView(context: Context) -> ImmediateKeyboardTriggerField {
        return ImmediateKeyboardTriggerField()
    }

    func updateUIView(_ uiView: ImmediateKeyboardTriggerField, context: Context) {}
}

// MARK: - View Extension
extension View {
    /// Triggers keyboard to appear immediately when view loads, synchronized with view animation.
    ///
    /// This is particularly useful for sheets/modals where you want the keyboard to animate
    /// in together with the sheet presentation, rather than appearing with a delay after the
    /// sheet is visible.
    ///
    /// **Example:**
    /// ```swift
    /// TextField("Enter text", text: $text)
    ///     .focused($isFocused)
    ///     .immediateKeyboard()
    ///     .onAppear { isFocused = true }
    /// ```
    func immediateKeyboard() -> some View {
        ZStack {
            // Hidden field that triggers keyboard at UIKit level
            ImmediateKeyboardTriggerView()
                .frame(width: 0, height: 0)
                .opacity(0)
            // Your actual content
            self
        }
    }
}
