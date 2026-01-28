import SwiftUI

// MARK: - Typography System
// The definitive typography system for the app following design specifications
// All text in the app should use these typography methods exclusively

// MARK: - Font Family Constants

/// The primary font family used throughout the app
/// Change this constant to update the font family everywhere
public let AppFontFamily = "Geist Mono"

/// The display font family used for titles
/// Variable font - use base family name without weight suffix
public let AppTitleFontFamily = "Stack Sans Notch"

// MARK: - Text Extension for Typography

extension Text {
    
    // MARK: - Typography Methods
    
    func headline() -> some View {
        self.font(Font.custom(AppFontFamily, size: 19))
            .lineSpacing(7.0)
            .kerning(-0.2)
    }

    func titleLarge() -> some View {
        self.font(Font.custom(AppTitleFontFamily, size: 20).weight(.medium))
            .lineSpacing(5)
            .kerning(-0.2)
    }

    /// Large stat/counter display (24pt)
    func stat() -> some View {
        self.font(Font.custom(AppFontFamily, size: 24))
            .lineSpacing(0)
            .kerning(-0.24)
    }

    func title() -> some View {
        self.font(Font.custom(AppTitleFontFamily, size: 17).weight(.medium))
            .lineSpacing(4)
            .kerning(-0.17)
    }

    func titleSmall() -> some View {
        self.font(Font.custom(AppTitleFontFamily, size: 15).weight(.medium))
            .lineSpacing(3)
            .kerning(0.65)
    }

    func bodyLarge() -> some View {
        self.font(Font.custom(AppFontFamily, size: 15))
            .lineSpacing(3.5) 
            .kerning(-0.15)
    }

    func body() -> some View {
        self.font(Font.custom(AppFontFamily, size: 13))
            .lineSpacing(1.5)
            .kerning(-0.15)
    }

    func bodySmall() -> some View {
        self.font(Font.custom(AppFontFamily, size: 11))
            .lineSpacing(3)
    }

    func caption() -> some View {
        self.font(Font.custom(AppFontFamily, size: 11).weight(.semibold))
            .lineSpacing(4.5) // 9pt * 1.5 - 9pt = 4.5pt
            .kerning(1.08) // 12% of 9pt
            .textCase(.uppercase)
    }

    func captionSmall() -> some View {
        self.font(Font.custom(AppFontFamily, size: 9))
            .lineSpacing(4.5) // 9pt * 1.5 - 9pt = 4.5pt
            .kerning(1.08) // 12% of 9pt
            .textCase(.uppercase)
    }
}

extension Font {
    // MARK: - Typography Fonts
    // Font versions of the typography system for use with TextField, Button, etc.

    static var headline: Font {
        Font.custom(AppFontFamily, size: 20)
    }

    static var stat: Font {
        Font.custom(AppFontFamily, size: 24)
    }

    static var title: Font {
        Font.custom(AppTitleFontFamily, size: 17)
    }

    static var titleSmall: Font {
        Font.custom(AppTitleFontFamily, size: 15)
    }

    static var bodyLarge: Font {
        Font.custom(AppFontFamily, size: 15)
    }

    static var body: Font {
        Font.custom(AppFontFamily, size: 13)
    }

    static var bodySmall: Font {
        Font.custom(AppFontFamily, size: 11)
    }

    static var caption: Font {
        Font.custom(AppFontFamily, size: 11)
    }

    static var captionSmall: Font {
        Font.custom(AppFontFamily, size: 9)
    }
    
    // MARK: - Utility Fonts
    
    static func symbol(size: CGFloat = 17) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
}
