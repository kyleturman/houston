import SwiftUI
import UIKit

/// Utility functions for color parsing and manipulation
///
/// Provides consistent color handling across the app, particularly for
/// hex color string parsing.
enum ColorHelpers {
    /// Parse hex color string to UIColor
    ///
    /// Supports multiple hex formats:
    /// - RGB (12-bit): "F00" → red
    /// - RGB (24-bit): "FF0000" → red
    /// - ARGB (32-bit): "FFFF0000" → red with alpha
    ///
    /// - Parameter hex: Hex color string (with or without # prefix)
    /// - Returns: Parsed UIColor or nil if invalid format
    ///
    /// **Usage:**
    /// ```swift
    /// let color = ColorHelpers.uiColor(from: "#FF5733")
    /// let color = ColorHelpers.uiColor(from: "FF5733")
    /// ```
    static func uiColor(from hex: String) -> UIColor? {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        return UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }

    /// Parse hex color string to SwiftUI Color
    ///
    /// Supports multiple hex formats:
    /// - RGB (12-bit): "F00" → red
    /// - RGB (24-bit): "FF0000" → red
    /// - ARGB (32-bit): "FFFF0000" → red with alpha
    ///
    /// - Parameter hex: Hex color string (with or without # prefix)
    /// - Returns: Parsed Color or nil if invalid format
    ///
    /// **Usage:**
    /// ```swift
    /// let color = ColorHelpers.color(from: "#FF5733")
    /// let color = ColorHelpers.color(from: "FF5733")
    /// ```
    static func color(from hex: String) -> Color? {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
