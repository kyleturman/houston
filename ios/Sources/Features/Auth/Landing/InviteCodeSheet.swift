import SwiftUI

struct InviteCodeSheet: View {
    @Environment(SessionManager.self) var session
    @Environment(\.dismiss) var dismiss

    @State private var inviteInput: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste invite link", text: $inviteInput)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: inviteInput) { _, _ in
                            if errorMessage != nil {
                                errorMessage = nil
                            }
                        }
                } footer: {
                    Text("Paste the invite link from your server administrator.")
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button {
                        Task {
                            await signIn()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Sign In")
                            }
                            Spacer()
                        }
                    }
                    .disabled(inviteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .navigationTitle("Sign In with Invite Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sign In

    private func signIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let trimmedInput = inviteInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let parsed = parseInviteLink(trimmedInput) else {
            errorMessage = "Invalid invite link. Make sure you copied the full link."
            return
        }

        // Create API client for this server
        let api = APIClient(baseURL: parsed.serverURL, deviceTokenProvider: { nil })

        // First verify server is reachable
        do {
            _ = try await api.up()
        } catch {
            errorMessage = "Cannot reach server. Check your network connection."
            return
        }

        // Try to claim the invite token
        do {
            let response = try await api.claimInviteToken(email: parsed.email, token: parsed.token)

            await MainActor.run {
                let name = response.server_name ?? parsed.serverURL.host ?? "My Server"
                session.addServer(name: name, url: parsed.serverURL, email: parsed.email)
                session.currentUserEmail = parsed.email
                session.deviceToken = response.device_token
                session.userToken = response.user_token
                session.onboardingCompleted = response.onboarding_completed
                session.emailEnabled = response.email_enabled ?? true
                dismiss()
            }
        } catch let error as APIClient.APIError {
            switch error {
            case .requestFailed(let statusCode, let message):
                if statusCode == 401 {
                    errorMessage = "Invalid or expired invite code"
                } else if statusCode == 404 {
                    errorMessage = "User not found. Check the invite link."
                } else {
                    errorMessage = message ?? "Sign in failed. Please try again."
                }
            default:
                errorMessage = "Sign in failed. Please try again."
            }
        } catch {
            errorMessage = "Sign in failed. Please check your connection."
        }
    }

    // MARK: - Link Parsing

    /// Parse an invite link and extract server URL, email, and token
    /// Supports: heyhouston://signin?url=...&email=...&token=...
    private func parseInviteLink(_ input: String) -> (serverURL: URL, email: String, token: String)? {
        guard let url = URL(string: input),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value)
        })

        guard let serverUrlStr = params["url"],
              let serverURL = URL(string: serverUrlStr),
              let email = params["email"],
              let token = params["token"] else {
            return nil
        }

        return (serverURL, email.lowercased(), token)
    }
}

#Preview {
    InviteCodeSheet()
        .environment(SessionManager(skipLoad: true))
}
