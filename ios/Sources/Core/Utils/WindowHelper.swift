import SwiftUI
import UIKit

/// Provides safe access to window metrics following iOS 18+ and Swift 6+ best practices.
/// All properties return safe fallback values if window is unavailable.
@MainActor
struct WindowHelper {
    
    // MARK: - Window Access
    
    /// Returns the key window from the active window scene.
    /// - Returns: The key window, or nil if unavailable
    private static var keyWindow: UIWindow? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return nil
        }
        return windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
    }
    
    // MARK: - Safe Area Insets
    
    /// Returns the top safe area inset (e.g., status bar, Dynamic Island).
    /// - Returns: Top safe area inset in points, or 52 as fallback for typical iPhone
    static var safeAreaTop: CGFloat {
        keyWindow?.safeAreaInsets.top ?? 52
    }
    
    /// Returns the bottom safe area inset (e.g., home indicator).
    /// - Returns: Bottom safe area inset in points, or 34 as fallback for typical iPhone with home indicator
    static var safeAreaBottom: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 34
    }
    
    /// Returns the leading safe area inset (e.g., notch on landscape).
    /// - Returns: Leading safe area inset in points, or 0 as fallback
    static var safeAreaLeading: CGFloat {
        keyWindow?.safeAreaInsets.left ?? 0
    }
    
    /// Returns the trailing safe area inset (e.g., notch on landscape).
    /// - Returns: Trailing safe area inset in points, or 0 as fallback
    static var safeAreaTrailing: CGFloat {
        keyWindow?.safeAreaInsets.right ?? 0
    }
    
    /// Returns all safe area insets as EdgeInsets.
    /// - Returns: EdgeInsets with all safe area values
    static var safeAreaInsets: EdgeInsets {
        EdgeInsets(
            top: safeAreaTop,
            leading: safeAreaLeading,
            bottom: safeAreaBottom,
            trailing: safeAreaTrailing
        )
    }
    
    // MARK: - Window Dimensions
    
    /// Returns the window width in points.
    /// - Returns: Window width, or screen width as fallback
    static var width: CGFloat {
        keyWindow?.bounds.width ?? UIScreen.main.bounds.width
    }
    
    /// Returns the window height in points.
    /// - Returns: Window height, or screen height as fallback
    static var height: CGFloat {
        keyWindow?.bounds.height ?? UIScreen.main.bounds.height
    }
    
    /// Returns the window size as CGSize.
    /// - Returns: Window size in points
    static var size: CGSize {
        CGSize(width: width, height: height)
    }
    
    // MARK: - Content Area (excluding safe areas)
    
    /// Returns the available content height (total height minus safe areas).
    /// - Returns: Content height in points
    static var contentHeight: CGFloat {
        height - safeAreaTop - safeAreaBottom
    }
    
    /// Returns the available content width (total width minus safe areas).
    /// - Returns: Content width in points
    static var contentWidth: CGFloat {
        width - safeAreaLeading - safeAreaTrailing
    }
    
    /// Returns the content area size (excluding all safe areas).
    /// - Returns: Content size in points
    static var contentSize: CGSize {
        CGSize(width: contentWidth, height: contentHeight)
    }
    
    // MARK: - Device Characteristics
    
    /// Returns true if the device has a notch or Dynamic Island.
    /// - Returns: True if top safe area is greater than 20 points
    static var hasNotch: Bool {
        safeAreaTop > 20
    }
    
    /// Returns true if the device has a home indicator (no home button).
    /// - Returns: True if bottom safe area is greater than 0
    static var hasHomeIndicator: Bool {
        safeAreaBottom > 0
    }
    
    // MARK: - Convenience Methods
    
    /// Returns the safe area insets as UIEdgeInsets for UIKit compatibility.
    /// - Returns: UIEdgeInsets with all safe area values
    static var uiSafeAreaInsets: UIEdgeInsets {
        keyWindow?.safeAreaInsets ?? UIEdgeInsets(
            top: 52,
            left: 0,
            bottom: 34,
            right: 0
        )
    }
}

// MARK: - SwiftUI Environment Extension

extension EnvironmentValues {
    /// Provides access to WindowHelper in SwiftUI views via @Environment.
    /// Usage: @Environment(\.windowHelper) var windowHelper
    var windowHelper: WindowHelper.Type {
        get { WindowHelper.self }
        set { }
    }
}
