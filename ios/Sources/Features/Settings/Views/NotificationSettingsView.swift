import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(NotificationManager.self) var notificationManager
    @Environment(\.dismiss) var dismiss

    @State private var isRequestingPermission = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: statusIcon)
                            .foregroundColor(statusColor)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications")
                                .font(.headline)

                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if notificationManager.authorizationStatus == .notDetermined ||
                           notificationManager.authorizationStatus == .denied {
                            Button(action: requestPermission) {
                                if isRequestingPermission {
                                    ProgressView()
                                } else {
                                    Text("Enable")
                                        .font(.callout.weight(.semibold))
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRequestingPermission)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Status")
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                }

                Section {
                    InfoRow(
                        icon: "sparkles",
                        title: "Daily Feed",
                        description: "Get notified when your morning, afternoon, or evening feed is ready with new insights and discoveries"
                    )
                } header: {
                    Text("Notification Types")
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                } footer: {
                    Text("Feed times are configured in your feed settings. You'll receive a notification each time new insights are generated.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if notificationManager.authorizationStatus == .denied {
                    Section {
                        Button(action: openSettings) {
                            HStack {
                                Image(systemName: "gear")
                                Text("Open Settings")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                        }
                    } footer: {
                        Text("Notifications are currently disabled in Settings. You'll need to enable them there to receive alerts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Status Helpers

    private var statusIcon: String {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "bell.fill"
        case .denied:
            return "bell.slash.fill"
        case .notDetermined:
            return "bell"
        @unknown default:
            return "bell"
        }
    }

    private var statusColor: Color {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var statusText: String {
        switch notificationManager.authorizationStatus {
        case .authorized:
            return "Enabled - You'll receive notifications"
        case .denied:
            return "Disabled - Enable in Settings to receive notifications"
        case .notDetermined:
            return "Not configured - Tap Enable to allow notifications"
        case .provisional:
            return "Provisional - Notifications delivered quietly"
        case .ephemeral:
            return "Ephemeral - Temporary authorization"
        @unknown default:
            return "Unknown status"
        }
    }

    // MARK: - Actions

    private func requestPermission() {
        isRequestingPermission = true

        Task {
            do {
                let granted = try await notificationManager.requestAuthorization()
                await MainActor.run {
                    isRequestingPermission = false
                }

                if !granted {
                    // User denied - show alert suggesting they enable in settings
                    print("[NotificationSettings] User denied notification permission")
                }
            } catch {
                await MainActor.run {
                    isRequestingPermission = false
                }
                print("[NotificationSettings] Error requesting permission: \(error)")
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Supporting Views

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NotificationSettingsView()
        .environment(NotificationManager.shared)
}
