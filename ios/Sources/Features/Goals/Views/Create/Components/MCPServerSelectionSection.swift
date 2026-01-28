import SwiftUI

struct MCPServerSelectionSection: View {
    @Binding var enabledMcpServers: [String]
    @Environment(SessionManager.self) var sessionManager
    @State private var availableServers: [MCPServer] = []
    @State private var isLoading = false
    
    var body: some View {
        Section(header: Text("Available Tools")) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if availableServers.isEmpty {
                Text("No tools available")
                    .font(.footnote)
                    .foregroundColor(Color.foreground["300"])
            } else {
                ForEach(availableServers) { server in
                    Toggle(isOn: Binding(
                        get: { enabledMcpServers.contains(server.apiName) },
                        set: { isEnabled in
                            if isEnabled {
                                enabledMcpServers.append(server.apiName)
                            } else {
                                enabledMcpServers.removeAll { $0 == server.apiName }
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundColor(Color.foreground["000"])
                                .font(.footnote)
                            Text(server.name)
                                .font(.footnote)
                                .foregroundColor(Color.foreground["000"])
                        }
                    }
                }
            }
            
            if !availableServers.isEmpty {
                Text("Select which tools the goal agent can use")
                    .font(.caption)
                    .foregroundColor(Color.foreground["300"])
            }
        }
        .task {
            await loadServers()
        }
    }
    
    private func loadServers() async {
        guard let baseURL = sessionManager.serverURL else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        let client = APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { sessionManager.deviceToken },
            userTokenProvider: { sessionManager.userToken }
        )
        
        do {
            let response = try await client.listMCPServers()
            
            // Filter to show servers that are ready for the user to use
            // Local servers:
            //   - No user auth required (e.g., brave-search with API key): show if available or connected
            //   - User auth required (e.g., plaid): only show if user has connected
            // Remote servers: must be connected or authorized
            // Default remote servers: excluded (not yet connected)
            availableServers = response.servers.filter { server in
                switch server.type {
                case .local:
                    // Servers with authType require user authentication
                    // Only show if user has actually connected
                    if server.authType != nil {
                        return server.connectionStatus == .connected
                    }
                    // Servers without authType (like brave-search) are ready when available
                    return server.connectionStatus == .connected || server.connectionStatus == .available
                case .remote:
                    return server.connectionStatus == .connected || server.connectionStatus == .authorized
                case .defaultRemote:
                    return false // Don't show until user connects them
                }
            }
        } catch {
            print("Error loading MCP servers: \(error)")
        }
    }
}
