import SwiftUI

/// Unified glass effect modifier that adapts based on iOS version
///
/// iOS 26+: Uses native `.glassEffect()` for authentic liquid glass
/// iOS 18-25: Uses `.ultraThinMaterial` with subtle styling for glassmorphism
///
/// Usage:
/// ```swift
/// MyView()
///     .glassBackground(cornerRadius: 24)
/// ```
extension View {
    /// Applies a glass effect background that adapts to the iOS version
    /// - Parameters:
    ///   - cornerRadius: The corner radius for the glass effect
    ///   - fill: Optional fill color to tint the glass (default: clear)
    ///   - strokeColor: Optional stroke color for the border (default: foreground with 10% opacity)
    ///   - strokeWidth: Border width (default: 0.5)
    @ViewBuilder
    func glassBackground(
        cornerRadius: CGFloat,
        fill: Color = .clear,
        strokeColor: Color? = nil,
        strokeWidth: CGFloat = 0.5
    ) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26+: Use authentic liquid glass effect
            self.background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(strokeColor ?? Color.foreground["000"].opacity(0.3), lineWidth: strokeWidth)
                    .glassEffect(.clear.tint(fill).interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            // iOS 18-25: Use glassmorphism with ultraThinMaterial
            self.background {
                ZStack {
                    // Base material blur
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)

                    // Subtle tint overlay
                    if fill != .clear {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(fill.opacity(0.3))
                    }

                    // Subtle border for definition
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            strokeColor ?? Color.foreground["000"].opacity(0.3),
                            lineWidth: strokeWidth
                        )
                }
            }
        }
    }

    /// Conditionally applies glass background only when `shouldApply` is true
    /// - Parameters:
    ///   - shouldApply: Whether to apply the glass effect
    ///   - cornerRadius: The corner radius for the glass effect
    ///   - fill: Optional fill color to tint the glass
    ///   - strokeColor: Optional stroke color for the border
    ///   - strokeWidth: Border width
    @ViewBuilder
    func glassBackgroundIf(
        _ shouldApply: Bool,
        cornerRadius: CGFloat,
        fill: Color = .clear,
        strokeColor: Color? = nil,
        strokeWidth: CGFloat = 0.5
    ) -> some View {
        if shouldApply {
            self.glassBackground(
                cornerRadius: cornerRadius,
                fill: fill,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth
            )
        } else {
            self
        }
    }
}

/// Preview demonstrating glass effect across different backgrounds
#Preview {
    ZStack {
        // Colorful background to show the glass effect
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 32) {
            Text("Glass Effect Examples")
                .font(.title.bold())
                .foregroundColor(.white)

            // Example 1: Clear glass
            VStack(spacing: 12) {
                Text("Clear Glass")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .glassBackground(cornerRadius: 24)

            // Example 2: Tinted glass
            VStack(spacing: 12) {
                Text("Tinted Glass")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .glassBackground(cornerRadius: 24, fill: Color.blue.opacity(0.2))

            // Example 3: Chat input style
            HStack {
                Text("Type a message...")
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassBackground(cornerRadius: 24)
            .padding(.horizontal, 20)
        }
        .padding()
    }
}
