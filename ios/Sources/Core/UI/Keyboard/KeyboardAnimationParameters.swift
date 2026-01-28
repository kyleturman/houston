import SwiftUI
import UIKit

/// Extracts and provides keyboard animation parameters from notifications.
///
/// **Why this exists:**
/// The iOS keyboard provides its own animation timing (duration + curve) in notifications.
/// To make our UI animate perfectly in sync with the keyboard, we need to extract these
/// parameters and use them instead of hardcoded values.
///
/// **The Problem:**
/// - If we use hardcoded timing (e.g., 0.25s), our views may lag behind or race ahead of the keyboard
/// - The keyboard's actual animation varies by device, iOS version, and context
///
/// **The Solution:**
/// - Extract the keyboard's actual animation parameters from the notification
/// - Provide both UIKit and SwiftUI versions for consistent animations across the app
/// - All keyboard-aware components use this shared utility for perfect synchronization
///
/// **Usage:**
/// ```swift
/// // In keyboard notification handler:
/// let params = KeyboardAnimationParameters(from: notification)
///
/// // UIKit:
/// UIView.animate(withDuration: params.duration, options: params.animationOptions) { ... }
///
/// // SwiftUI:
/// withAnimation(params.swiftUIAnimation) { ... }
/// ```
struct KeyboardAnimationParameters {
    let duration: Double
    let curve: UIView.AnimationCurve
    let animationOptions: UIView.AnimationOptions

    /// Extract parameters from keyboard notification
    init(from notification: Notification) {
        // Extract duration (fallback to 0.25s if not provided)
        self.duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25

        // Extract animation curve (fallback to easeInOut if not provided)
        let curveValue = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        self.curve = UIView.AnimationCurve(rawValue: Int(curveValue)) ?? .easeInOut

        // Create UIKit animation options with the curve embedded
        // The shift by 16 bits is required by UIView.AnimationOptions to properly encode the curve
        self.animationOptions = UIView.AnimationOptions(rawValue: curveValue << 16)
    }

    /// Convert to SwiftUI Animation
    ///
    /// Maps UIKit animation curves to their SwiftUI equivalents.
    /// This ensures SwiftUI views can animate with the exact same timing as UIKit views.
    var swiftUIAnimation: Animation {
        switch curve {
        case .easeInOut: return .easeInOut(duration: duration)
        case .easeIn: return .easeIn(duration: duration)
        case .easeOut: return .easeOut(duration: duration)
        case .linear: return .linear(duration: duration)
        @unknown default: return .easeInOut(duration: duration)
        }
    }
}
