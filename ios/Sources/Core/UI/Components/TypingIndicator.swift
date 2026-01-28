import SwiftUI

/// A classic three-dot bouncing animation for indicating typing/thinking state.
/// Height matches one line of body text for seamless integration.
struct TypingIndicator: View {
    @State private var animatingDot = 0
    @State private var timer: Timer?
    @State private var isVisible = false

    /// Dot size - slightly smaller than body text for visual balance
    private let dotSize: CGFloat = 6
    /// Spacing between dots
    private let spacing: CGFloat = 4
    /// Interval between dot bounces
    private let bounceInterval: Double = 0.3
    /// Bounce height
    private let bounceOffset: CGFloat = -4
    /// Duration for the entrance animation
    private let entranceAnimationDuration: Double = 0.3

    /// Match StreamingText height (font size 13 + line spacing 3)
    private var targetHeight: CGFloat {
        // StreamingText uses .font(.custom(AppFontFamily, size: 13)) with .lineSpacing(3)
        // Approximate the line height to match
        16 + 3 // font ascender + descender (~16) + line spacing (3)
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.foreground["100"])
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: animatingDot == index ? bounceOffset : 0)
                    .animation(
                        .easeInOut(duration: bounceInterval * 0.8),
                        value: animatingDot
                    )
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(height: isVisible ? targetHeight : 0)
        .clipped()
        .onAppear {
            withAnimation(.easeOut(duration: entranceAnimationDuration)) {
                isVisible = true
            }
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
            isVisible = false
        }
    }

    private func startAnimation() {
        // Invalidate any existing timer
        timer?.invalidate()

        // Create a repeating timer for the bounce cycle
        timer = Timer.scheduledTimer(withTimeInterval: bounceInterval, repeats: true) { _ in
            Task { @MainActor in
                animatingDot = (animatingDot + 1) % 3
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Regular body text for comparison")
            .font(.body)

        HStack {
            TypingIndicator()
            Spacer()
        }

        Text("More text below")
            .font(.body)
    }
    .padding()
}
