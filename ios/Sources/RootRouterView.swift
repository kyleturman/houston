import SwiftUI

struct RootRouterView: View {
    @Environment(SessionManager.self) var session
    @Environment(NetworkMonitor.self) var networkMonitor
    @Environment(StateManager.self) var stateManager

    var body: some View {
        ZStack {
            switch session.phase {
            case .loading:
                // Show space background while loading - matches LandingView for seamless transition
                GeometryReader { geometry in
                    Image("space-background")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            case .landing, .onboarding:
                // LandingView handles both landing and onboarding phases
                // It displays sign-in card for landing, onboarding card for onboarding
                LandingView()
            case .main:
                MainNavigationContainer()
                    .ignoresSafeArea(.container)
            }

            // Server unavailable overlay - shows when server is unreachable but we have credentials
            if session.serverUnavailable && session.userToken != nil {
                ServerUnavailableOverlay()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.serverUnavailable)
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            // Auto-retry connection when network comes back online
            if isConnected && session.serverUnavailable && !session.isRetryingConnection {
                Task {
                    // Small delay to let network stabilize
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    await session.retryConnection()
                }
            }
        }
        .onChange(of: session.phase) { oldPhase, newPhase in
            // Connect/disconnect SSE based on authentication state
            if newPhase == .main && oldPhase != .main {
                // User just authenticated - connect SSE
                stateManager.connect(session: session)
            } else if newPhase == .landing && oldPhase != .landing {
                // User signed out - disconnect SSE
                stateManager.disconnect()
            }
        }
        .onChange(of: session.serverUnavailable) { wasUnavailable, isUnavailable in
            // Reconnect SSE when server becomes available
            if wasUnavailable && !isUnavailable && session.phase == .main {
                stateManager.connect(session: session)
            }
        }
        .withToastContainer()
    }
}

// MARK: - Server Unavailable Overlay
struct ServerUnavailableOverlay: View {
    @Environment(SessionManager.self) var session
    @Environment(RememberedUserStore.self) var rememberedUserStore

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Card with server info and retry
                VStack(spacing: 20) {
                    // Icon and title
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(Color.foreground["200"])

                        Text("Server Unavailable")
                            .title()
                            .foregroundColor(Color.foreground["000"])

                        Text("Unable to connect to your server. Check your internet connection and ensure server is started and try again.")
                            .body()
                            .foregroundColor(Color.foreground["300"])
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    // Server info card
                    VStack(spacing: 8) {
                        if let serverName = session.currentServerName {
                            HStack {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.foreground["400"])
                                Text(serverName)
                                    .bodySmall()
                                    .foregroundColor(Color.foreground["200"])
                                Spacer()
                            }
                        }

                        if let email = session.currentUserEmail {
                            HStack {
                                Image(systemName: "envelope")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.foreground["400"])
                                Text(email)
                                    .bodySmall()
                                    .foregroundColor(Color.foreground["200"])
                                Spacer()
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.background["100"])
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.border["000"], lineWidth: 1)
                    )
                    .cornerRadius(12)

                    // Retry button
                    Button(action: {
                        Task {
                            await session.retryConnection()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if session.isRetryingConnection {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(session.isRetryingConnection ? "Connecting..." : "Retry Connection")
                        }
                        .font(.bodyLarge)
                        .foregroundColor(Color.background["000"])
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.foreground["100"])
                        .cornerRadius(12)
                    }
                    .disabled(session.isRetryingConnection)

                    // Sign out option
                    Button(action: {
                        // Remember user before signing out for easy re-authentication
                        if let serverURL = session.serverURL,
                           let serverName = session.currentServerName,
                           let email = session.currentUserEmail {
                            rememberedUserStore.remember(serverURL: serverURL, serverName: serverName, email: email, emailEnabled: session.emailEnabled)
                        }
                        session.signOutUser()
                    }) {
                        Text("Sign Out")
                            .body()
                            .foregroundColor(Color.foreground["400"])
                    }
                }
                .padding(24)
                .background(Color.background["000"])
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.border["000"], lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                .padding(.horizontal, 12)
                .padding(.bottom, 40)
            }
        }
    }
}
