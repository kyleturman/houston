import SwiftUI

/*
 =========================================
  Color Quick Access Helpers (Read Me First)
  -----------------------------------------
  Use these helpers to fetch theme colors dynamically:

    Color.background["000"]
    Color.foreground["300"]
    Color.border["000"]

  To introspect keys for a category:

    Color.background.availableKeys

  Colors update automatically when system/app appearance changes.
 =========================================
*/

// MARK: - Dynamic Color Extensions for Theme Access
extension Color {
    
    // MARK: - Dynamic Color Category Access
    struct DynamicColorCategory {
        private let category: String
        
        init(_ category: String) {
            self.category = category
        }
        
        /// Access colors using subscript syntax: Color.background["000"]
        @MainActor
        subscript(key: String) -> Color {
            ThemeManager.shared.color(category: category, key: key)
        }
        
        /// Get all available keys for this category
        @MainActor
        var availableKeys: [String] {
            ThemeManager.shared.availableKeys(for: category)
        }
    }
    
    // MARK: - Quick Access Helpers (Static Category Accessors)
    // Usage:
    //   Color.background["000"]
    //   Color.foreground["300"]
    //   Color.border["000"]
    //   Color.semantic["success"]
    // Introspection:
    //   Color.background.availableKeys
    static let background = DynamicColorCategory("background")
    static let foreground = DynamicColorCategory("foreground")
    static let border = DynamicColorCategory("border")
    static let semantic = DynamicColorCategory("semantic")
    
    // MARK: - Accent Color Support
    /// Get default accent color (foreground 000)
    @MainActor
    static func accent() -> Color {
        return Color.foreground["000"]
    }
    
    /// Get accent color for a goal, or default if goal is nil or has no accent color
    @MainActor
    static func accent(_ goal: Goal?) -> Color {
        guard let goal = goal,
              let accentColorHex = goal.accentColor,
              !accentColorHex.isEmpty else {
            return Color.foreground["000"]
        }
        
        // Check if it's a predefined accent color
        if let predefinedColor = ThemeManager.shared.accentColor(named: accentColorHex) {
            return predefinedColor
        }
        
        // Try to parse as hex color
        if let hexColor = ColorHelpers.color(from: accentColorHex) {
            return hexColor
        }
        return Color.foreground["000"]
    }
}

// Color hex support now provided by ColorHelpers utility


