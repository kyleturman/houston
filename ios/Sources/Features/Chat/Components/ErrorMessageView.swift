import SwiftUI

/// Error message component with distinct styling for system errors
/// Includes Retry and Dismiss buttons for user control
struct ErrorMessageView: View {
    let message: ChatMessage
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?

    /// Initialize with message only (backwards compatible, no actions)
    init(message: ChatMessage) {
        self.message = message
        self.onRetry = nil
        self.onDismiss = nil
    }

    /// Initialize with message and action callbacks
    init(message: ChatMessage, onRetry: (() -> Void)?, onDismiss: (() -> Void)?) {
        self.message = message
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)

                Text("Error")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)

                Spacer()

                // Dismiss button (X)
                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(message.content)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Retry button
            if let onRetry = onRetry {
                HStack {
                    Spacer()
                    Button(action: onRetry) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                            Text("Retry")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorMessageView(message: ChatMessage(
            id: "1",
            content: "400 error with provider API",
            source: .error,
            createdAt: Date()
        ))

        ErrorMessageView(
            message: ChatMessage(
                id: "2",
                content: "Hitting rate limits, will retry in a moment",
                source: .error,
                createdAt: Date()
            ),
            onRetry: { print("Retry tapped") },
            onDismiss: { print("Dismiss tapped") }
        )

        ErrorMessageView(
            message: ChatMessage(
                id: "3",
                content: "Connection timeout, will retry automatically",
                source: .error,
                createdAt: Date()
            ),
            onRetry: { print("Retry tapped") },
            onDismiss: { print("Dismiss tapped") }
        )
    }
    .padding()
}
