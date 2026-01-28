import SwiftUI
import Foundation
import Observation

// MARK: - Theme Manager
@MainActor
@Observable
class ThemeManager {
    static let shared = ThemeManager()

    var currentTheme: String {
        didSet {
            saveThemePreference()
        }
    }

    var followSystemAppearance: Bool {
        didSet {
            saveSystemAppearancePreference()
        }
    }
    
    private let colorSystem = ColorSystem.shared
    private let userDefaults = UserDefaults.standard
    
    // UserDefaults keys
    private let themeKey = "selectedTheme"
    private let followSystemKey = "followSystemAppearance"
    
    private init() {
        // Load saved preferences - default to following system appearance
        let savedFollowSystem = userDefaults.object(forKey: followSystemKey) as? Bool ?? true
        self.followSystemAppearance = savedFollowSystem
        
        if savedFollowSystem {
            // Use system appearance - will be updated by SwiftUI environment
            self.currentTheme = "light" // Default, will be overridden by environment
        } else {
            // Use saved theme or default to light
            self.currentTheme = userDefaults.string(forKey: themeKey) ?? "light"
        }
    }
    
    // MARK: - Public API
    
    /// Get all available themes from the color system
    var availableThemes: [String] {
        colorSystem.availableThemes
    }
    
    /// Get current theme colors
    var currentThemeColors: ThemeColors? {
        colorSystem.colors(for: currentTheme)
    }

    /// Effective color scheme for the app. If following system appearance,
    /// return nil so we don't force any scheme and let the system drive it.
    var effectiveColorScheme: ColorScheme? {
        guard !followSystemAppearance else { return nil }
        return currentTheme == "dark" ? .dark : .light
    }
    
    /// Set a specific theme
    func setTheme(_ theme: String) {
        guard availableThemes.contains(theme) else {
            print("⚠️ ThemeManager: Theme '\(theme)' not available")
            return
        }
        currentTheme = theme
    }
    
    /// Toggle between light and dark themes
    func toggleTheme() {
        currentTheme = currentTheme == "dark" ? "light" : "dark"
    }
    
    /// Update theme based on SwiftUI environment (called from SwiftUI views)
    func updateFromEnvironment(_ colorScheme: ColorScheme) {
        guard followSystemAppearance else { return }
        
        let systemTheme = colorScheme == .dark ? "dark" : "light"
        if currentTheme != systemTheme {
            currentTheme = systemTheme
        }
    }
    
    // MARK: - Color Access Methods
    
    /// Get a color for the current theme by category and key
    func color(category: String, key: String) -> Color {
        // Use dynamic color so that when system/app scheme changes,
        // the color re-resolves automatically.
        colorSystem.getDynamicColor(category: category, key: key)
    }
    
    /// Get all available categories for the current theme
    var availableCategories: [String] {
        colorSystem.getAvailableCategories(for: currentTheme)
    }
    
    /// Get all available keys for a category in the current theme
    func availableKeys(for category: String) -> [String] {
        colorSystem.getAvailableKeys(for: currentTheme, category: category)
    }
    
    /// Get an accent color by name from the predefined accent colors
    func accentColor(named name: String) -> Color? {
        colorSystem.getAccentColor(named: name)
    }
    
    /// Get all available accent colors
    var availableAccentColors: [String: String] {
        colorSystem.availableAccentColors
    }
    
    // MARK: - Private Methods
    
    private func saveThemePreference() {
        userDefaults.set(currentTheme, forKey: themeKey)
    }
    
    private func saveSystemAppearancePreference() {
        userDefaults.set(followSystemAppearance, forKey: followSystemKey)
    }
}
