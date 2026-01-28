import SwiftUI
import UIKit

/// Manages keyboard height tracking with the ability to freeze the inset value.
///
/// Use this when presenting sheets from a view with keyboard open - freeze the inset
/// before the sheet opens to prevent content from jumping when the keyboard dismisses.
///
/// **Usage:**
/// ```swift
/// @Environment(KeyboardInsetManager.self) var keyboardInsetManager
///
/// // In your view that presents sheets:
/// .onChange(of: someSheetIsPresented) { wasPresented, isPresented in
///     if isPresented && !wasPresented {
///         keyboardInsetManager.freeze()
///     } else if !isPresented && wasPresented {
///         keyboardInsetManager.unfreeze()
///     }
/// }
///
/// // Pass to child views:
/// ChatView(bottomInset: keyboardInsetManager.effectiveBottomInset)
/// ```
@MainActor
@Observable
final class KeyboardInsetManager: @unchecked Sendable {
    // MARK: - Properties

    /// Current keyboard height from system notifications
    private(set) var currentKeyboardHeight: CGFloat = 0

    /// Frozen inset value - when set, effectiveBottomInset returns this instead of current
    private var frozenInset: CGFloat?

    /// Whether the inset is currently frozen
    var isFrozen: Bool {
        frozenInset != nil
    }

    /// The effective bottom inset to use for layout.
    /// Returns the frozen value if set, otherwise the current keyboard height.
    var effectiveBottomInset: CGFloat {
        frozenInset ?? currentKeyboardHeight
    }

    // MARK: - Initialization

    init() {
        setupKeyboardObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Freeze a specific inset value.
    /// Call this before presenting a sheet to prevent content jumping.
    /// - Parameter value: The inset value to freeze (e.g., current bottomInset)
    func freeze(value: CGFloat) {
        guard frozenInset == nil else { return }
        frozenInset = value
    }

    /// Freeze the current keyboard height as the inset value.
    /// Call this before presenting a sheet to prevent content jumping.
    func freeze() {
        freeze(value: currentKeyboardHeight)
    }

    /// Unfreeze the inset, returning to live keyboard tracking.
    /// Call this after the sheet is dismissed.
    func unfreeze() {
        frozenInset = nil
    }

    // MARK: - Private Methods

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidShow(_:)),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        currentKeyboardHeight = frame.height
    }

    @objc private func keyboardDidShow(_ notification: Notification) {
        // Auto-unfreeze after keyboard animation completes - this ensures smooth transition
        // when returning from a sheet that dismissed the keyboard
        // Small delay to ensure everything has settled
        if isFrozen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.frozenInset = nil
            }
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        currentKeyboardHeight = 0
    }
}
