import SwiftUI

/// Sign-in card component for LandingView that handles both fresh sign-in and remembered user states
struct LandingSignInCard: View {
    @Environment(SessionManager.self) var session
    @Environment(RememberedUserStore.self) var rememberedUserStore

    let showInviteCodeSheet: () -> Void

    @State private var isRequestingSignIn = false
    @State private var signInRequestSent = false

    var body: some View {
        VStack(spacing: 8) {
            if let remembered = rememberedUserStore.rememberedUser {
                rememberedUserContent(remembered)
            } else {
                signedOutContent
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .glassBackground(cornerRadius: 20)
    }

    // MARK: - Signed Out Content

    private var signedOutContent: some View {
        VStack(spacing: 8) {
            // Error message (if any)
            if let error = session.signInError {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Sign In Error")
                            .font(.headline)
                            .foregroundStyle(.red)
                    }

                    Text(error)
                        .body()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    Button("Dismiss") {
                        session.signInError = nil
                    }
                    .font(.body)
                    .foregroundStyle(.blue)
                }
                .padding(.bottom, 8)
            }

            (Text("To continue, open link from sign-in email or ")
                .foregroundStyle(.white)
            + Text("use server invite code")
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            ThemeManager.shared.accentColor(named: "coral") ?? .red,
                            ThemeManager.shared.accentColor(named: "orange") ?? .orange,
                            ThemeManager.shared.accentColor(named: "yellow") ?? .yellow,
                            ThemeManager.shared.accentColor(named: "chartreuse") ?? .green,
                            ThemeManager.shared.accentColor(named: "lime") ?? .green,
                            ThemeManager.shared.accentColor(named: "mint") ?? .mint,
                            ThemeManager.shared.accentColor(named: "sky") ?? .cyan,
                            ThemeManager.shared.accentColor(named: "blue") ?? .blue,
                            ThemeManager.shared.accentColor(named: "purple") ?? .purple,
                            ThemeManager.shared.accentColor(named: "magenta") ?? .pink
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
            .body()
            .multilineTextAlignment(.center)
            .onTapGesture {
                showInviteCodeSheet()
            }
        }
    }

    // MARK: - Remembered User Content

    private func rememberedUserContent(_ remembered: RememberedUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Server info
            VStack(alignment: .leading, spacing: 4) {
                Text(remembered.serverName)
                    .title()
                    .foregroundStyle(.white)

                // Replace characters that cause unwanted line breaks with non-breaking equivalents:
                // - hyphen → non-breaking hyphen (U+2011)
                // - colon → colon + word joiner (U+2060) to prevent break after ://
                // - slash → slash + word joiner (U+2060) to prevent break after
                // - period → period + word joiner (U+2060) to prevent break after
                // - underscore → underscore + word joiner (U+2060) to prevent break after
                Text(remembered.serverURL
                    .replacingOccurrences(of: "-", with: "\u{2011}")
                    .replacingOccurrences(of: ":", with: ":\u{2060}")
                    .replacingOccurrences(of: "/", with: "/\u{2060}")
                    .replacingOccurrences(of: ".", with: ".\u{2060}")
                    .replacingOccurrences(of: "_", with: "_\u{2060}"))
                    .body()
                    .foregroundStyle(.white.opacity(0.6))

                Text(remembered.email)
                    .body()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Success message after requesting sign-in
            if signInRequestSent {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Sign-in link sent! Check your email.")
                        .body()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.4))
                .cornerRadius(12)
                .padding(.top, 8)
            }

            // Info message when email is not configured
            if !remembered.emailEnabled {
                Text("Email sign-in is not available for this server. Use an invite code to sign back in.")
                    .body()
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
            }

            // Action buttons
            HStack(spacing: 16) {
                // Sign back in button (only show if email is enabled)
                if remembered.emailEnabled {
                    Button {
                        Task {
                            await requestSignIn(email: remembered.email, serverURL: remembered.serverURL)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isRequestingSignIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane")
                                    .font(.system(size: 14))
                            }
                            Text("Sign back in")
                                .body()
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.white)
                    }
                    .disabled(isRequestingSignIn || signInRequestSent)
                    .opacity(signInRequestSent ? 0.5 : 1)
                }

                // Invite code button (show when email not enabled)
                if !remembered.emailEnabled {
                    Button {
                        showInviteCodeSheet()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 14))
                            Text("Use invite code")
                                .body()
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.white)
                    }
                }

                // Sign out button (forget user)
                Button {
                    rememberedUserStore.forget()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14))
                        Text("Sign out")
                            .body()
                    }
                    .foregroundStyle(ThemeManager.shared.accentColor(named: "coral") ?? .red)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func requestSignIn(email: String, serverURL: String) async {
        guard let url = URL(string: serverURL) else { return }

        isRequestingSignIn = true
        defer { isRequestingSignIn = false }

        let api = APIClient(baseURL: url, deviceTokenProvider: { nil })

        do {
            _ = try await api.requestSignin(email: email)
            signInRequestSent = true
        } catch {
            // Show error via session
            session.signInError = "Failed to send sign-in link. Please try again."
        }
    }
}
