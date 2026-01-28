import SwiftUI

struct AccountMenuSheet: View {
    @Environment(SessionManager.self) var session
    @Environment(NavigationViewModel.self) var navigationVM
    @Environment(RememberedUserStore.self) var rememberedUserStore
    @Environment(\.dismiss) var dismiss

    @State private var showingProfileEdit = false

    /// Calculate sheet height based on content
    private var sheetHeight: CGFloat {
        var height: CGFloat = 0
        height += 110 // Server info box (name, url, email + padding)
        height += 96 // Menu items (2 items)
        if session.servers.count > 1 {
            height += 50 // Section header + divider
            height += CGFloat(session.servers.count * 64) // Account switcher items
        }
        height += 16 // Bottom padding
        return height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Server and account info box
            VStack(alignment: .leading, spacing: 4) {
                Text(session.currentServerName ?? "Server")
                    .title()
                    .foregroundColor(Color.foreground["000"])

                if let serverURL = session.serverURL?.absoluteString {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(serverURL)
                            .bodySmall()
                            .foregroundColor(Color.foreground["300"])
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(session.currentUserEmail ?? "Unknown")
                    .bodySmall()
                    .foregroundColor(Color.foreground["300"])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.border["000"], lineWidth: 1)
            )
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 8)

            // Menu items
            VStack(alignment: .leading, spacing: 0) {
                // Edit Profile - doesn't dismiss, shows nested sheet
                Button {
                    showingProfileEdit = true
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 17))
                            .foregroundColor(Color.foreground["000"])
                            .frame(width: 24)
                        Text("Edit Profile")
                            .bodyLarge()
                            .foregroundColor(Color.foreground["000"])
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Log Out - dismisses and signs out
                Button {
                    // Remember user before signing out for easy re-authentication
                    if let serverURL = session.serverURL,
                       let serverName = session.currentServerName,
                       let email = session.currentUserEmail {
                        rememberedUserStore.remember(serverURL: serverURL, serverName: serverName, email: email, emailEnabled: session.emailEnabled)
                    }
                    dismiss()
                    session.signOutUser()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 17))
                            .foregroundColor(Color.semantic["error"])
                            .frame(width: 24)
                        Text("Log Out")
                            .bodyLarge()
                            .foregroundColor(Color.semantic["error"])
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            // Show accounts section only if there are multiple accounts
            if session.servers.count > 1 {
                Divider()
                    .background(Color.border["000"])
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                // Accounts Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Switch Account")
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                        .padding(.horizontal, 20)

                    ForEach(session.servers) { server in
                        AccountSwitcherItem(
                            email: server.email ?? "Unknown",
                            serverName: server.name,
                            isSelected: session.selectedServerId == server.id
                        ) {
                            session.selectServer(id: server.id)
                            dismiss()
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }

            Spacer()
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
        .sheet(isPresented: $showingProfileEdit) {
            UserProfileSheet()
                .environment(session)
        }
    }
}

// Account switcher item component
struct AccountSwitcherItem: View {
    let email: String
    let serverName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(email)
                        .bodyLarge()
                        .foregroundColor(Color.foreground["000"])

                    Text(serverName)
                        .body()
                        .foregroundColor(Color.foreground["300"])
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color.semantic["success"])
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isSelected ? Color.background["200"] : Color.background["100"])
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    let session = {
        let s = SessionManager()
        s.currentUserName = "Kyle"
        s.currentUserEmail = "kyle@example.com"
        return s
    }()

    let goalsVM = GoalsViewModel(session: session)
    let navVM = NavigationViewModel(goalsViewModel: goalsVM)

    return AccountMenuSheet()
        .environment(session)
        .environment(navVM)
}
