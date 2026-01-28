import SwiftUI

struct AccentColorPickerButton: View {
    @Binding var selectedColor: String?
    @Binding var showingPicker: Bool
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        Section {
            Button {
                showingPicker = true
            } label: {
                HStack {
                    Text("Accent color")
                        .foregroundColor(.primary)
                    Spacer()
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(getPreviewColor())
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.border["000"], lineWidth: 1)
                        )
                    
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    @MainActor
    private func getPreviewColor() -> Color {
        guard let accentColor = selectedColor, !accentColor.isEmpty else {
            return getDefaultAccentColor()
        }
        
        if let predefinedColor = themeManager.accentColor(named: accentColor) {
            return predefinedColor
        }
        
        if let hexColor = ColorHelpers.color(from: accentColor) {
            return hexColor
        }
        
        return getDefaultAccentColor()
    }
    
    @MainActor
    private func getDefaultAccentColor() -> Color {
        let availableColors = themeManager.availableAccentColors
        if let firstColorName = availableColors.keys.sorted().first,
           let defaultColor = themeManager.accentColor(named: firstColorName) {
            return defaultColor
        }
        return Color.accent()
    }
}
