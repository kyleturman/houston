import SwiftUI

struct MenuItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let isDestructive: Bool
    let action: () -> Void

    init(icon: String, title: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.isDestructive = isDestructive
        self.action = action
    }
}

struct MenuSheet: View {
    let items: [MenuItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        item.action()
                    }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17))
                            .foregroundColor(item.isDestructive ? Color.semantic["error"] : Color.foreground["000"])
                            .frame(width: 24)

                        Text(item.title)
                            .bodyLarge()
                            .foregroundColor(item.isDestructive ? Color.semantic["error"] : Color.foreground["000"])

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    static func height(for itemCount: Int) -> CGFloat {
        // Base padding (8 top + 8 bottom) + item height (52 per item)
        CGFloat(16 + (itemCount * 52))
    }
}
