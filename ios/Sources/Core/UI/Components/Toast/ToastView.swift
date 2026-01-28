import SwiftUI

/// Visual representation of a toast notification
struct ToastView: View {
    let toast: ToastItem
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    private let dismissThreshold: CGFloat = -50

    var body: some View {
        HStack(spacing: 12) {
            if toast.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .foregroundColor(Color.foreground["300"])
            } else {
                Image(systemName: toast.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.foreground["300"])
            }

            Text(toast.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(Color.foreground["100"])
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 17)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.background["100"])
                .stroke(Color.foreground["500"].opacity(0.2), lineWidth: 1)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 8)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    // Only allow upward dragging
                    if gesture.translation.height < 0 {
                        dragOffset = gesture.translation.height
                    }
                }
                .onEnded { gesture in
                    if gesture.translation.height < dismissThreshold {
                        // Dismiss with animation
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = -200
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDismiss()
                        }
                    } else {
                        // Spring back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

/// Container that shows toasts at the top of the screen
struct ToastContainerView: View {
    @State private var toastManager = ToastManager.shared

    var body: some View {
        VStack {
            if let toast = toastManager.currentToast {
                ToastView(toast: toast) {
                    toastManager.dismiss()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
            Spacer()
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: toastManager.currentToast)
    }
}
