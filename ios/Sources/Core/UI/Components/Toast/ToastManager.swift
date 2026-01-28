import SwiftUI
import Observation

/// Manages toast notifications throughout the app
@MainActor
@Observable
final class ToastManager: @unchecked Sendable {
    static let shared = ToastManager()

    private(set) var currentToast: ToastItem?
    private var toastQueue: [ToastItem] = []
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Show a toast notification
    func show(_ message: String, type: ToastType = .info, duration: TimeInterval = 3.0) {
        let toast = ToastItem(message: message, type: type, duration: duration, isLoading: false)

        if currentToast == nil {
            presentToast(toast)
        } else {
            toastQueue.append(toast)
        }
    }

    /// Show a loading toast that persists until updated
    /// Returns an ID that can be used to update the toast
    func showLoading(_ message: String) -> UUID {
        let toast = ToastItem(message: message, type: .info, duration: .infinity, isLoading: true)

        // Cancel existing dismiss task and clear queue for loading toasts
        dismissTask?.cancel()

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentToast = toast
        }

        return toast.id
    }

    /// Update the current loading toast to a final state
    func updateToast(id: UUID, message: String, type: ToastType, autoDismiss: Bool = true) {
        guard currentToast?.id == id else { return }

        let updatedToast = ToastItem(id: id, message: message, type: type, duration: autoDismiss ? 3.0 : .infinity, isLoading: false)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentToast = updatedToast
        }

        if autoDismiss {
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(updatedToast.duration * 1_000_000_000))
                if !Task.isCancelled {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        if currentToast?.id == id {
                            currentToast = nil
                        }
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if !Task.isCancelled {
                        showNextToastIfNeeded()
                    }
                }
            }
        }
    }

    /// Dismiss the current toast
    func dismiss() {
        dismissTask?.cancel()
        currentToast = nil
        showNextToastIfNeeded()
    }

    private func presentToast(_ toast: ToastItem) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentToast = toast
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                    currentToast = nil
                }
                // Small delay before showing next toast
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                if !Task.isCancelled {
                    showNextToastIfNeeded()
                }
            }
        }
    }

    private func showNextToastIfNeeded() {
        guard !toastQueue.isEmpty else { return }
        let nextToast = toastQueue.removeFirst()
        presentToast(nextToast)
    }
}

/// Represents a single toast notification
struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let message: String
    let type: ToastType
    let duration: TimeInterval
    let isLoading: Bool

    init(id: UUID = UUID(), message: String, type: ToastType, duration: TimeInterval, isLoading: Bool = false) {
        self.id = id
        self.message = message
        self.type = type
        self.duration = duration
        self.isLoading = isLoading
    }
}

/// Toast notification types
enum ToastType {
    case success
    case error
    case warning
    case info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle"
        case .error: return "xmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }

    @MainActor
    var color: Color {
        switch self {
        case .success: return Color.semantic["success"]
        case .error: return Color.semantic["error"]
        case .warning: return Color.semantic["warning"]
        case .info: return Color.semantic["info"]
        }
    }
}
