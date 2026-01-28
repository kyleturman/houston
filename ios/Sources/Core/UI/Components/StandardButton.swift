import SwiftUI

struct StandardButton<Content: View>: View {
    enum Variant {
        case fill
        case outline
        case glass
    }

    enum Size {
        case standard
        case large

        var height: CGFloat {
            switch self {
            case .standard: return 48
            case .large: return 60
            }
        }

        var font: Font {
            switch self {
            case .standard: return .body
            case .large: return .title3
            }
        }
    }

    let variant: Variant
    let size: Size
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void
    let content: Content

    init(
        variant: Variant = .fill,
        size: Size = .standard,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.size = size
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Content (hidden when loading)
                content
                    .opacity(isLoading ? 0 : 1)

                // Loading spinner
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foregroundColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: size.height)
            .padding(.horizontal, 20)
            .background(backgroundView)
            .foregroundColor(foregroundColor)
            .glassBackgroundIf(variant == .glass, cornerRadius: 14)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(borderOverlay)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(BounceButtonStyle())
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.5 : 1)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .fill:
            Color.foreground["000"]
        case .outline, .glass:
            Color.clear
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .fill:
            return Color.background["000"]
        case .outline:
            return Color.foreground["100"]
        case .glass:
            return Color.foreground["000"]
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if case .outline = variant {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.border["200"], lineWidth: 1.5)
        }
    }
}

extension StandardButton where Content == AnyView {
    init(
        title: String,
        icon: String? = nil,
        variant: Variant = .fill,
        size: Size = .standard,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(variant: variant, size: size, isLoading: isLoading, isDisabled: isDisabled, action: action) {
            AnyView(
                HStack(spacing: 8) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .light))
                    }
                    Text(title)
                        .bodyLarge()
                }
            )
        }
    }
}

#Preview {
    ZStack {
        // Colorful background to show glass effect
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 20) {
            StandardButton(title: "Create Goal", icon: "plus.circle", action: {})

            StandardButton(title: "Secondary Action", variant: .outline, action: {})

            StandardButton(title: "Glass Button", icon: "sparkles", variant: .glass, action: {})

            StandardButton(title: "Loading...", isLoading: true, action: {})

            StandardButton(title: "Disabled", isDisabled: true, action: {})

            StandardButton(variant: .glass, action: {}) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("User Name")
                        Text("user@example.com").font(.caption)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
    }
}
