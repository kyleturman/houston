import SwiftUI
import Combine

// MARK: - Shimmer Effect

/// A reusable shimmer/gradient animation effect that can be applied to any SwiftUI view.
/// Commonly used for loading states, "thinking" indicators, and skeleton screens.
///
/// Usage:
/// ```swift
/// Text("Loading...")
///     .shimmer()
///
/// Text("Custom shimmer")
///     .shimmer(duration: 2.0, bounce: true)
/// ```
struct ShimmerEffect: ViewModifier {
    let duration: Double
    let bounce: Bool
    let opacity: Double
    
    @State private var isInitialState = true
    
    // Gradient configuration
    private let bandSize: CGFloat = 0.3
    private var min: CGFloat { 0 - bandSize }
    private var max: CGFloat { 1 + bandSize }
    
    private var gradient: Gradient {
        Gradient(colors: [
            .white.opacity(opacity * 0.8),
            .white,
            .white.opacity(opacity * 0.8)
        ])
    }
    
    // Animate gradient diagonally from top-left to bottom-right
    private var startPoint: UnitPoint {
        isInitialState ? UnitPoint(x: min, y: min) : UnitPoint(x: 1, y: 1)
    }
    
    private var endPoint: UnitPoint {
        isInitialState ? UnitPoint(x: 0, y: 0) : UnitPoint(x: max, y: max)
    }

    func body(content: Content) -> some View {
        content
            .mask(
                LinearGradient(
                    gradient: gradient,
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )
            .animation(
                .linear(duration: duration)
                    .repeatForever(autoreverses: bounce),
                value: isInitialState
            )
            .onAppear {
                // Trigger animation on next run loop
                DispatchQueue.main.async {
                    isInitialState = false
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Applies a horizontal shimmer/gradient animation to the view.
    ///
    /// - Parameters:
    ///   - isActive: Whether the shimmer should be active (default: true)
    ///   - duration: Duration of one shimmer cycle in seconds (default: 1.5)
    ///   - bounce: Whether to bounce back and forth (default: false)
    ///   - opacity: Opacity of the shimmer highlight (default: 0.5)
    /// - Returns: The view with shimmer effect applied
    func shimmer(
        isActive: Bool = true,
        duration: Double = 1.5,
        bounce: Bool = false,
        opacity: Double = 0.5
    ) -> some View {
        Group {
            if isActive {
                self
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(ShimmerEffect(
                        duration: duration,
                        bounce: bounce,
                        opacity: opacity
                    ))
            } else {
                self
            }
        }
    }
    
    /// Applies an animated shimmer effect to the view's border
    ///
    /// - Parameters:
    ///   - isActive: Whether the shimmer animation should be active
    ///   - baseColor: The base color of the border
    ///   - accentColor: The accent color that creates the shimmer effect
    ///   - lineWidth: Width of the border line
    ///   - cornerRadius: Corner radius of the border
    ///   - duration: Duration of one shimmer cycle in seconds (default: 2.0)
    /// - Returns: The view with animated border shimmer applied
    func shimmerBorder(
        isActive: Bool,
        baseColor: Color,
        accentColor: Color,
        lineWidth: CGFloat,
        cornerRadius: CGFloat,
        duration: Double = 5
    ) -> some View {
        self.overlay(
            Group {
                if isActive {
                    ShimmerBorderModifier(
                        accentColor: accentColor,
                        baseColor: baseColor,
                        lineWidth: lineWidth,
                        cornerRadius: cornerRadius,
                        duration: duration
                    )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(baseColor, lineWidth: lineWidth)
                }
            }
        )
    }
}

// MARK: - Rainbow Border Modifier

/// A continuously rotating rainbow gradient border using multiple colors
struct RainbowBorderModifier: View {
    let colors: [Color]
    let baseColor: Color
    let lineWidth: CGFloat
    let cornerRadius: CGFloat
    let duration: Double

    @State private var rotation: Double = 0

    private var gradientStops: [Gradient.Stop] {
        guard !colors.isEmpty else {
            return [.init(color: .clear, location: 0), .init(color: .clear, location: 1)]
        }

        var stops: [Gradient.Stop] = []
        let colorCount = colors.count

        for (index, color) in colors.enumerated() {
            let location = Double(index) / Double(colorCount)
            stops.append(.init(color: color, location: location))
        }
        // Close the loop by repeating the first color at the end
        stops.append(.init(color: colors[0], location: 1.0))

        return stops
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base border
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(baseColor, lineWidth: lineWidth)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // Animated rainbow gradient overlay
                AngularGradient(
                    stops: gradientStops,
                    center: .center
                )
                .rotationEffect(.degrees(rotation), anchor: .center)
                .frame(
                    width: max(geometry.size.width, geometry.size.height) * 1.5,
                    height: max(geometry.size.width, geometry.size.height) * 1.5
                )
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(lineWidth: lineWidth)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(
            .linear(duration: duration)
            .repeatForever(autoreverses: false),
            value: rotation
        )
        .onAppear {
            DispatchQueue.main.async {
                rotation = 360
            }
        }
    }
}

extension View {
    /// Applies a continuously rotating rainbow gradient border using multiple colors
    ///
    /// - Parameters:
    ///   - colors: Array of colors to use in the gradient
    ///   - baseColor: The base/background color of the border
    ///   - lineWidth: Width of the border line
    ///   - cornerRadius: Corner radius of the border
    ///   - duration: Duration of one full rotation in seconds
    /// - Returns: The view with animated rainbow border applied
    func rainbowBorder(
        colors: [Color],
        baseColor: Color = Color.border["000"],
        lineWidth: CGFloat = 1,
        cornerRadius: CGFloat = 8,
        duration: Double = 8
    ) -> some View {
        self.overlay(
            RainbowBorderModifier(
                colors: colors,
                baseColor: baseColor,
                lineWidth: lineWidth,
                cornerRadius: cornerRadius,
                duration: duration
            )
        )
    }
}

// MARK: - Shimmer Border Modifier

private struct ShimmerBorderModifier: View {
    let accentColor: Color
    let baseColor: Color
    let lineWidth: CGFloat
    let cornerRadius: CGFloat
    let duration: Double

    @State private var rotation: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base border - matches actual view dimensions
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(baseColor, lineWidth: lineWidth)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // Animated gradient overlay - square aspect ratio for consistent rotation
                AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.2),
                        .init(color: accentColor, location: 0.5),
                        .init(color: .clear, location: 0.8),
                        .init(color: .clear, location: 1.0)
                    ],
                    center: .center,
                )
                .rotationEffect(.degrees(rotation), anchor: UnitPoint(x: 0.5, y: 0.5))
                .frame(
                    width: max(geometry.size.width, geometry.size.height),
                    height: max(geometry.size.width, geometry.size.height)
                )
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(lineWidth: lineWidth)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(
            .linear(duration: duration)
            .repeatForever(autoreverses: false),
            value: rotation
        )
        .onAppear {
            // Trigger animation on next run loop
            DispatchQueue.main.async {
                rotation = -360
            }
        }
    }
}
