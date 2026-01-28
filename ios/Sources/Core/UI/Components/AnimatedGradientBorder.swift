import SwiftUI

struct AnimatedGradientBorder: View {
    let cornerRadius: CGFloat
    let phase: CGFloat
    
    private let accentColors: [Color] = [
        Color(hex: "#66D9A6"), // mint
        Color(hex: "#33DD33"), // lime
        Color(hex: "#6CB039"), // chartreuse
        Color(hex: "#DDDD66"), // yellow
        Color(hex: "#DD9966"), // orange
        Color(hex: "#DD6666"), // coral
        Color(hex: "#DD66BB"), // magenta
        Color(hex: "#8866DD"), // purple
        Color(hex: "#4466DD"), // blue
        Color(hex: "#66AADD"), // sky
        Color(hex: "#66D9A6"), // mint (repeat for seamless loop)
    ]
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .fill(
                AngularGradient(
                    colors: accentColors,
                    center: .center,
                    angle: .degrees(Double(360 * phase))
                )
            )
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

#Preview {
    VStack {
        Text("Animated Gradient Border")
            .padding(40)
    }
    .overlay(
        AnimatedGradientBorder(cornerRadius: 20, phase: 0.5)
    )
    .padding()
}
