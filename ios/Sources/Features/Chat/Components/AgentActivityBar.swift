import SwiftUI

/// A compact status bar showing current agent activity
/// Displays above chat input with accent color background
struct AgentActivityBar: View {
    let statusText: String
    let accentColor: String?

    private var backgroundColor: Color {
        if let accentColor = accentColor,
           let color = ThemeManager.shared.accentColor(named: accentColor) {
            return color
        }
        // Fallback to mint if no accent color
        return ThemeManager.shared.accentColor(named: "mint") ?? Color.semantic["info"]
    }

    var body: some View {
        HStack {
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(backgroundColor)
    }
}
