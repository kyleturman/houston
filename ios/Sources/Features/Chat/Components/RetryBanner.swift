import SwiftUI

struct RetryBanner: View {
    let task: AgentTaskModel
    let onRetry: () -> Void
    
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        HStack(spacing: 12) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color.semantic["warning"])
                .font(.system(size: 16, weight: .medium))
            
            VStack(alignment: .leading, spacing: 2) {
                // Error message
                Text(task.userFriendlyErrorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                // Retry status
                if !task.retryStatusText.isEmpty {
                    Text(task.retryStatusText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Retry button
            Button(action: onRetry) {
                Text("Retry")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .disabled(!task.isRetryable)
            .opacity(task.isRetryable ? 1.0 : 0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startTimer() {
        updateTimeRemaining()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                updateTimeRemaining()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateTimeRemaining() {
        timeRemaining = task.timeUntilRetry ?? 0
    }
}

#Preview {
    VStack(spacing: 0) {
        // Rate limit example
        RetryBanner(
            task: AgentTaskModel(
                id: "1",
                title: "Test Task",
                instructions: nil,
                status: .paused,
                priority: .normal,
                goalId: nil,
                createdAt: nil,
                updatedAt: nil,
                errorType: "rate_limit",
                errorMessage: "Rate limit exceeded",
                retryCount: 1,
                nextRetryAt: Date().addingTimeInterval(120),
                cancelledReason: nil
            ),
            onRetry: {}
        )
        
        Divider()
        
        // Network error example
        RetryBanner(
            task: AgentTaskModel(
                id: "2",
                title: "Test Task 2",
                instructions: nil,
                status: .paused,
                priority: .normal,
                goalId: nil,
                createdAt: nil,
                updatedAt: nil,
                errorType: "network",
                errorMessage: "Connection timeout",
                retryCount: 2,
                nextRetryAt: Date().addingTimeInterval(-10), // Ready to retry
                cancelledReason: nil
            ),
            onRetry: {}
        )
    }
}
