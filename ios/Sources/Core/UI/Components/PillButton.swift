import SwiftUI

/// Reusable pill-shaped button with optional color accent
/// Used for goal selection, tags, filters, etc.
struct PillButton: View {
    let title: String
    let isSelected: Bool
    let color: Color?
    let action: () -> Void

    init(
        title: String,
        isSelected: Bool = false,
        color: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? effectiveColor : Color.gray.opacity(0.2))
                )
        }
    }

    private var effectiveColor: Color {
        color ?? .blue
    }
}

// MARK: - Convenience Initializers

extension PillButton {
    /// Create pill button from hex color string
    init(
        title: String,
        isSelected: Bool = false,
        hexColor: String?,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            isSelected: isSelected,
            color: hexColor.flatMap { ColorHelpers.color(from: $0) },
            action: action
        )
    }
}
