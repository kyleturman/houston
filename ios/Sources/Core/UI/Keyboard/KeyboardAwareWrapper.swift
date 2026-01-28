import SwiftUI
import UIKit

/// A reusable wrapper that makes any SwiftUI view keyboard-aware by animating layout constraints.
///
/// **Why UIKit constraints instead of transforms:**
///
/// When mixing UIKit and SwiftUI, there are two separate "worlds" for layout:
///
/// 1. **Model Layer (Layout)**: The actual position of views based on constraints/frames
///    - This is what SwiftUI reads to calculate its layouts
///    - Changing constraints updates this layer
///
/// 2. **Presentation Layer (Visual)**: What you see on screen after transforms are applied
///    - CGAffineTransform only changes the presentation, not the model
///    - SwiftUI cannot see transform changes
///
/// **The Problem with Transforms:**
/// ```swift
/// // Using CGAffineTransform:
/// view.transform = CGAffineTransform(translationX: 0, y: -300)
/// // View LOOKS like it's at Y: -300 (presentation)
/// // But SwiftUI thinks it's still at Y: 0 (model)
/// // When SwiftUI recalculates layout → jump/glitch!
/// ```
///
/// **Why Constraints Work:**
/// ```swift
/// // Using constraint animation:
/// bottomConstraint.constant = -300
/// layoutIfNeeded()
/// // View IS at Y: -300 (model)
/// // SwiftUI sees the same position (model)
/// // Both systems agree → smooth animations!
/// ```
///
/// **Key Takeaway:**
/// When embedding UIKit views in SwiftUI (via UIViewRepresentable), always animate the MODEL layer
/// (constraints, frames) not just the PRESENTATION layer (transforms). This keeps both layout
/// systems synchronized.
///
/// **Usage:**
/// ```swift
/// FooterActionBar()
///     .keyboardAware()  // Moves up/down with keyboard smoothly
/// ```
struct KeyboardAwareWrapper<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> KeyboardAwareHostView<Content> {
        return KeyboardAwareHostView(content: content)
    }

    func updateUIView(_ uiView: KeyboardAwareHostView<Content>, context: Context) {
        uiView.updateContent(content)
    }
}

class KeyboardAwareHostView<Content: View>: UIView {
    private var hostingController: UIHostingController<Content>!
    private var bottomConstraint: NSLayoutConstraint!

    init(content: Content) {
        super.init(frame: .zero)
        setupView(with: content)
        setupKeyboardObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor deinit {
        cleanupKeyboardObservers()
    }

    func updateContent(_ content: Content) {
        hostingController.rootView = content
    }

    override var intrinsicContentSize: CGSize {
        return hostingController.view.intrinsicContentSize
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        return hostingController.view.systemLayoutSizeFitting(targetSize)
    }

    private func setupView(with content: Content) {
        // Create SwiftUI view inside UIHostingController
        hostingController = UIHostingController(rootView: content)

        // Disable safe area insets to prevent extra padding
        hostingController.safeAreaRegions = []

        // Add hosting controller's view as subview
        addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        // Pin hosting controller to fill the wrapper
        // Use the bottom constraint for keyboard animation
        bottomConstraint = hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        // Lower priority to avoid conflicts with intrinsic size during keyboard animations
        bottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomConstraint
        ])

        // Let the content determine its own height
        hostingController.view.setContentHuggingPriority(.required, for: .vertical)
        hostingController.view.setContentCompressionResistancePriority(.required, for: .vertical)

        // Make wrapper itself shrink to fit content
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func cleanupKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let params = KeyboardAnimationParameters(from: notification)

        UIView.animate(
            withDuration: params.duration,
            delay: 0,
            options: [params.animationOptions, .beginFromCurrentState],
            animations: {
                // Update the constraint constant (model layer)
                self.bottomConstraint.constant = -frame.height

                // CRITICAL: Force layout update inside animation block
                // This ensures UIKit recalculates all frames based on the new constraint
                // before the animation completes, keeping the model layer in sync
                self.layoutIfNeeded()
            },
            completion: nil
        )
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        let params = KeyboardAnimationParameters(from: notification)

        UIView.animate(
            withDuration: params.duration,
            delay: 0,
            options: [params.animationOptions, .beginFromCurrentState],
            animations: {
                // Reset the constraint constant
                self.bottomConstraint.constant = 0

                // Force layout update (see keyboardWillShow for explanation)
                self.layoutIfNeeded()
            },
            completion: nil
        )
    }
}

// MARK: - Convenience Extensions
extension View {
    /// Makes any SwiftUI view keyboard-aware using keyboard notifications
    func keyboardAware() -> some View {
        KeyboardAwareWrapper {
            self
        }
    }
}
