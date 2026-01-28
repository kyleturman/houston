import SwiftUI

/// Button style that provides a bounce animation on tap
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Reusable 48x48 icon button with liquid glass or custom background support
struct IconButton: View {
    let iconName: String
    let action: (() -> Void)?
    let backgroundColor: Color?
    let foregroundColor: Color
    let rounded: Bool
    
    /// Creates an IconButton with liquid glass background (default)
    /// - Parameters:
    ///   - iconName: SF Symbols icon name
    ///   - action: Optional action to perform when tapped
    ///   - foregroundColor: Color for the icon (default: foreground["000"])
    ///   - rounded: Whether to make the button circular (default: false)
    init(
        iconName: String,
        action: (() -> Void)? = nil,
        foregroundColor: Color = Color.foreground["000"],
        rounded: Bool = false
    ) {
        self.iconName = iconName
        self.action = action
        self.backgroundColor = nil
        self.foregroundColor = foregroundColor
        self.rounded = rounded
    }
    
    /// Creates an IconButton with custom background color
    /// - Parameters:
    ///   - iconName: SF Symbols icon name
    ///   - backgroundColor: Custom background color
    ///   - action: Optional action to perform when tapped
    ///   - foregroundColor: Color for the icon (default: background["000"])
    ///   - rounded: Whether to make the button circular (default: false)
    init(
        iconName: String,
        backgroundColor: Color,
        action: (() -> Void)? = nil,
        foregroundColor: Color = Color.background["000"],
        rounded: Bool = false
    ) {
        self.iconName = iconName
        self.action = action
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.rounded = rounded
    }
    
    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    iconContent
                }
                .buttonStyle(BounceButtonStyle())
            } else {
                iconContent
            }
        }
        .background(buttonBackground)
        .glassBackgroundIf(backgroundColor == nil, cornerRadius: cornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    private var iconContent: some View {
        Image(systemName: iconName)
            .font(.title2)
            .foregroundColor(foregroundColor)
            .frame(width: 48, height: 48)
    }
    
    private var cornerRadius: CGFloat {
        rounded ? 100 : 12
    }
    
    @ViewBuilder
    private var buttonBackground: some View {
        if let backgroundColor = backgroundColor {
            // Custom background color
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
        } else {
            // Transparent background for proper liquid glass effect
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.clear)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Liquid glass menu button
        IconButton(
            iconName: "line.3.horizontal",
            action: { print("Menu tapped") }
        )
        
        // Accent color plus button
        IconButton(
            iconName: "plus",
            backgroundColor: .blue,
            action: { print("Plus tapped") }
        )
        
        HStack(spacing: 12) {
            IconButton(
                iconName: "heart.fill",
                backgroundColor: .red,
                action: { print("Heart tapped") },
                foregroundColor: .white
            )
            
            IconButton(
                iconName: "star.fill",
                backgroundColor: .yellow,
                action: { print("Star tapped") },
                foregroundColor: .black
            )
            
            IconButton(
                iconName: "gearshape.fill",
                action: { print("Settings tapped") }
            )
        }
    }
    .padding()
    .background(Color.background["100"])
}
