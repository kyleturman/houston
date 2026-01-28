import SwiftUI
import Foundation
import UIKit
import Observation

// MARK: - Color Configuration Models
struct ColorConfiguration: Codable {
    let themes: [String: ThemeColors]
    let accents: [String: String]?
}

// UIColor hex support now provided by ColorHelpers utility

struct ThemeColors: Codable {
    let categories: [String: ColorShades]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        categories = try container.decode([String: ColorShades].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(categories)
    }
}

struct ColorShades: Codable {
    private let shades: [String: String]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        shades = try container.decode([String: String].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(shades)
    }
    
    /// Get color for a shade key (e.g., "000", "100", "200")
    func color(for shade: String) -> String? {
        return shades[shade]
    }
    
    /// Get all available shade keys
    var availableShades: [String] {
        return Array(shades.keys).sorted()
    }
}


// MARK: - Color System Service
@MainActor
@Observable
class ColorSystem {
    static let shared = ColorSystem()
    
    private var configuration: ColorConfiguration?
    private let configFileName = "colors"
    
    private init() {
        loadConfiguration()
    }
    
    private func loadConfiguration() {
        guard let url = Bundle.main.url(forResource: configFileName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("❌ ColorSystem: Failed to load colors.json from bundle. This file is required for the app to function.")
        }
        
        do {
            configuration = try JSONDecoder().decode(ColorConfiguration.self, from: data)
            validateConfiguration()
            print("✅ ColorSystem: Successfully loaded and validated color configuration")
        } catch {
            fatalError("❌ ColorSystem: Failed to decode colors.json - \(error)")
        }
    }
    
    /// Validates that all themes in the configuration have consistent structure.
    /// This prevents runtime crashes by ensuring all themes have the same color keys.
    /// Called automatically during ColorSystem initialization.
    private func validateConfiguration() {
        guard let config = configuration else {
            fatalError("❌ ColorSystem: No configuration to validate")
        }
        
        guard !config.themes.isEmpty else {
            fatalError("❌ ColorSystem: No themes found in colors.json")
        }
        
        // Get the first theme as the reference structure
        let themeNames = Array(config.themes.keys).sorted()
        guard let referenceThemeName = themeNames.first,
              let referenceTheme = config.themes[referenceThemeName] else {
            fatalError("❌ ColorSystem: Unable to get reference theme")
        }
        
        print("🔍 ColorSystem: Using '\(referenceThemeName)' as reference theme for validation")
        
        // Collect reference categories dynamically from the reference theme
        let referenceCategories = Set(referenceTheme.categories.keys)
        
        // Validate all other themes match the reference structure (categories and their keys)
        for (themeName, theme) in config.themes {
            if themeName == referenceThemeName { continue }

            // First ensure categories match
            let themeCategories = Set(theme.categories.keys)
            if themeCategories != referenceCategories {
                let missingCats = referenceCategories.subtracting(themeCategories)
                let extraCats = themeCategories.subtracting(referenceCategories)
                var errorMessage = "❌ ColorSystem: Theme '\(themeName)' has inconsistent categories compared to '\(referenceThemeName)'"
                if !missingCats.isEmpty {
                    errorMessage += "\n   Missing categories: \(missingCats.sorted().joined(separator: ", "))"
                }
                if !extraCats.isEmpty {
                    errorMessage += "\n   Extra categories: \(extraCats.sorted().joined(separator: ", "))"
                }
                fatalError(errorMessage)
            }

            // Then ensure each category has the same keys
            for category in referenceCategories {
                guard let refShades = referenceTheme.categories[category],
                      let themeShades = theme.categories[category] else { continue }
                let refKeys = Set(refShades.availableShades)
                let themeKeys = Set(themeShades.availableShades)
                if refKeys != themeKeys {
                    let missing = refKeys.subtracting(themeKeys)
                    let extra = themeKeys.subtracting(refKeys)
                    var errorMessage = "❌ ColorSystem: Theme '\(themeName)' category '\(category)' has inconsistent keys compared to '\(referenceThemeName)'"
                    if !missing.isEmpty {
                        errorMessage += "\n   Missing keys: \(missing.sorted().joined(separator: ", "))"
                    }
                    if !extra.isEmpty {
                        errorMessage += "\n   Extra keys: \(extra.sorted().joined(separator: ", "))"
                    }
                    fatalError(errorMessage)
                }
            }
        }
        
        print("✅ ColorSystem: All \(config.themes.count) themes have consistent structure")
        print("   - Categories: \(referenceCategories.sorted().joined(separator: ", "))")
    }
    
    // MARK: - Public API
    
    /// Get all available theme names
    var availableThemes: [String] {
        configuration?.themes.keys.sorted() ?? []
    }
    
    /// Get colors for a specific theme
    func colors(for theme: String) -> ThemeColors? {
        configuration?.themes[theme]
    }
    
    /// Convert hex string to SwiftUI Color
    func color(from hex: String) -> Color {
        ColorHelpers.color(from: hex) ?? .primary
    }
    
    /// Get a color by theme, category, and key (resolved immediately, not trait-dynamic)
    func getColor(theme: String, category: String, key: String) -> Color {
        guard let themeColors = colors(for: theme) else {
            print("⚠️ ColorSystem: Theme '\(theme)' not found, using fallback")
            return .primary
        }
        
        guard let hex = themeColors.categories[category]?.color(for: key) else {
            print("⚠️ ColorSystem: Color key '\(key)' not found in category '\(category)' for theme '\(theme)'")
            return .primary
        }
        
        return color(from: hex)
    }

    /// Get a Color that dynamically resolves based on the current interface style (light/dark).
    /// This uses a dynamic UIColor provider so that when the system/app color scheme changes,
    /// SwiftUI re-resolves the color automatically without requiring explicit view invalidation.
    func getDynamicColor(category: String, key: String) -> Color {
        let dynamic = UIColor { traits in
            let themeName = (traits.userInterfaceStyle == .dark) ? "dark" : "light"
            guard let themeColors = self.colors(for: themeName) else {
                return UIColor.label
            }

            guard let hex = themeColors.categories[category]?.color(for: key),
                  let ui = ColorHelpers.uiColor(from: hex) else {
                return UIColor.label
            }
            return ui
        }
        return Color(dynamic)
    }
    
    /// Get all available categories for a theme
    func getAvailableCategories(for theme: String) -> [String] {
        guard let themeColors = colors(for: theme) else { return [] }
        return themeColors.categories.keys.sorted()
    }
    
    /// Get all available keys for a category in a theme
    func getAvailableKeys(for theme: String, category: String) -> [String] {
        guard let themeColors = colors(for: theme) else { return [] }
        return themeColors.categories[category]?.availableShades ?? []
    }
    
    /// Get all available accent colors
    var availableAccentColors: [String: String] {
        configuration?.accents ?? [:]
    }
    
    /// Get an accent color by name
    func getAccentColor(named name: String) -> Color? {
        guard let hex = configuration?.accents?[name] else { return nil }
        return ColorHelpers.color(from: hex)
    }
}

