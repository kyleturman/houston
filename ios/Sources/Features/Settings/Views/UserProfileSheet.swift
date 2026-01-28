import SwiftUI

struct UserProfileSheet: View {
    @Environment(SessionManager.self) var sessionManager
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        TextField("Your Name", text: $name)
                            .textContentType(.name)
                            .autocapitalization(.words)

                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                    } header: {
                        Text("Account Information")
                            .caption()
                            .foregroundColor(Color.foreground["300"])
                    }

                    if let error = error {
                        Section {
                            Text(error)
                                .foregroundColor(Color.semantic["error"])
                                .bodyLarge()
                        }
                    }
                }

                // Bottom Save Button
                StandardButton(
                    title: "Save",
                    isLoading: isSaving,
                    isDisabled: isSaveDisabled,
                    action: { Task { await saveProfile() } }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .bodyLarge()
                            .foregroundColor(Color.foreground["000"])
                    }
                }
            }
            .onAppear {
                // Pre-fill with current data
                name = sessionManager.currentUserName ?? ""
                email = sessionManager.currentUserEmail ?? ""
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private var isSaveDisabled: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty
    }

    private func saveProfile() async {
        isSaving = true
        error = nil
        defer { isSaving = false }

        guard let baseURL = sessionManager.serverURL else {
            error = "Server URL not found"
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            error = "Name cannot be empty"
            return
        }

        let client = APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { self.sessionManager.deviceToken },
            userTokenProvider: { self.sessionManager.userToken }
        )

        do {
            let emailChanged = trimmedEmail != sessionManager.currentUserEmail

            let response = try await client.updateUserProfile(
                name: trimmedName,
                email: emailChanged ? trimmedEmail : nil
            )

            // Update session manager with new data
            await MainActor.run {
                sessionManager.currentUserName = response.name
                sessionManager.currentUserEmail = response.email

                // Show success toast
                ToastManager.shared.show("Profile updated", type: .success)

                dismiss()
            }
        } catch {
            if let apiError = error as? APIClient.APIError {
                switch apiError {
                case .requestFailed(_, let message):
                    self.error = message ?? "Failed to update profile"
                default:
                    self.error = "Failed to update profile: \(error.localizedDescription)"
                }
            } else {
                self.error = "Failed to update profile: \(error.localizedDescription)"
            }

            // Show error toast
            await MainActor.run {
                ToastManager.shared.show("Failed to update profile", type: .error)
            }
        }
    }
}

#Preview {
    UserProfileSheet()
        .environment({
            let session = SessionManager()
            session.currentUserName = "Kyle"
            session.currentUserEmail = "kyle@example.com"
            return session
        }())
}
