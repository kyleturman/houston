import SwiftUI

/// Persistent connectivity status banner that appears at the top of the screen
/// Extends behind the status bar and Dynamic Island for a native iOS feel
///
/// **Design Pattern:**
/// - Background color extends into safe area (behind status bar/Dynamic Island)
/// - Content respects safe area (text appears below Dynamic Island)
/// - Pushes main content down (doesn't overlay)
/// - Auto-dismisses after 2s for "back online" state
///
/// **Visual Hierarchy:**
/// ```
/// ┌─────────────────────────────────┐
/// │ ●●● Dynamic Island ●●●          │ <- Status bar (background color extends here)
/// ├─────────────────────────────────┤
/// │ 🔴 No internet connection       │ <- Banner content (below Dynamic Island)
/// ├─────────────────────────────────┤
/// │ Main App Content (pushed down)  │
/// ```
///
/// Usage:
/// ```swift
/// VStack(spacing: 0) {
///     if networkMonitor.showBanner {
///         ConnectivityBanner(status: networkMonitor.status)
///             .transition(.move(edge: .top).combined(with: .opacity))
///     }
///     MainContent()
/// }
/// ```
struct ConnectivityBanner: View {
    let status: NetworkMonitor.Status

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: iconName)
                .font(.caption)
                .foregroundColor(.white)

            // Text
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

            // Spinner for reconnecting state
            if status == .reconnecting {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(backgroundColor.ignoresSafeArea(edges: .top))
        .safeAreaInset(edge: .top) {
            // This creates proper spacing for the status bar/Dynamic Island
            Color.clear.frame(height: 0)
        }
    }

    // MARK: - Private Helpers

    private var iconName: String {
        switch status {
        case .offline:
            return "wifi.slash"
        case .reconnecting:
            return "arrow.clockwise"
        case .online:
            return "checkmark.circle.fill"
        }
    }

    private var message: String {
        switch status {
        case .offline:
            return "No internet connection"
        case .reconnecting:
            return "Connecting..."
        case .online:
            return "Back online"
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .offline:
            return Color(red: 1.0, green: 0.6, blue: 0.0) // Orange
        case .reconnecting:
            return Color(red: 1.0, green: 0.8, blue: 0.0) // Yellow
        case .online:
            return Color(red: 0.2, green: 0.8, blue: 0.2) // Green
        }
    }
}

// MARK: - Previews

#Preview("Offline") {
    VStack(spacing: 0) {
        ConnectivityBanner(status: .offline)

        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<20) { index in
                    Text("Item \(index)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}

#Preview("Reconnecting") {
    VStack(spacing: 0) {
        ConnectivityBanner(status: .reconnecting)

        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<20) { index in
                    Text("Item \(index)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}

#Preview("Back Online") {
    VStack(spacing: 0) {
        ConnectivityBanner(status: .online)

        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<20) { index in
                    Text("Item \(index)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}
