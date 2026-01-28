import SwiftUI

struct MCPIntegrationsView: View {
    @Environment(SessionManager.self) var session
    @State private var viewModel = MCPIntegrationsViewModel()
    @State private var showingAddServer = false
    @State private var showLoadingHint = false

    /// Servers that are fully enabled (no auth needed OR auth needed and connected)
    private var enabledServers: [MCPServer] {
        let allServers = viewModel.localServers + viewModel.remoteServers + viewModel.defaultServers
        return allServers.filter { server in
            let requiresAuth = (server.type != .local) || (server.connectionStrategy != nil)
            let isConnected = server.connectionStatus == .connected || server.connectionStatus == .authorized

            if requiresAuth {
                return isConnected
            } else {
                // No auth required - enabled if available
                return server.connectionStatus == .available || server.connectionStatus == .connected
            }
        }
    }

    /// Servers that need auth but user hasn't connected yet
    private var availableServers: [MCPServer] {
        let allServers = viewModel.localServers + viewModel.remoteServers + viewModel.defaultServers
        return allServers.filter { server in
            let requiresAuth = (server.type != .local) || (server.connectionStrategy != nil)
            let isConnected = server.connectionStatus == .connected || server.connectionStatus == .authorized

            // Needs auth and not connected
            return requiresAuth && !isConnected && server.connectionStatus != .needsSetup
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.loading {
                    Section {
                        VStack(spacing: 0) {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 20)

                            Text("May take a few more seconds to warm up servers")
                                .caption()
                                .foregroundColor(Color.foreground["300"])
                                .opacity(showLoadingHint ? 1 : 0)
                        }
                    }
                    .task(id: viewModel.loading) {
                        showLoadingHint = false
                        try? await Task.sleep(for: .seconds(2))
                        if viewModel.loading {
                            withAnimation(.easeIn(duration: 0.3)) {
                                showLoadingHint = true
                            }
                        }
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Error loading servers")
                                .headline()
                                .foregroundColor(Color.semantic["error"])
                            Text(errorMessage)
                                .caption()
                                .foregroundColor(.secondary)
                            Button("Retry") {
                                Task {
                                    await viewModel.loadServers()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                } else {
                    // Top group: Enabled servers (no auth needed OR connected)
                    if !enabledServers.isEmpty {
                        Section {
                            ForEach(enabledServers) { server in
                                NavigationLink(value: server) {
                                    MCPServerRow(server: server, viewModel: viewModel)
                                }
                            }
                        }
                    }

                    // Available: Need auth but not connected yet (plus Add Custom Server)
                    Section {
                        ForEach(availableServers) { server in
                            NavigationLink(value: server) {
                                MCPServerRow(server: server, viewModel: viewModel)
                            }
                        }

                        // Add Custom Server button
                        Button {
                            showingAddServer = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Add remote server")
                                        .bodyLarge()
                                        .foregroundColor(Color.foreground["000"])

                                    Text("Connect to MCP server via url")
                                        .bodySmall()
                                        .foregroundColor(Color.foreground["300"])
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color.semantic["primary"])
                            }
                            .padding(.vertical, 4)
                        }
                        .foregroundColor(.primary)
                    } header: {
                        if !availableServers.isEmpty {
                            Text("Available")
                                .caption()
                                .foregroundColor(Color.foreground["300"])
                        }
                    }

                    // Disabled/Unconfigured servers
                    if !viewModel.unconfiguredServers.isEmpty {
                        Section {
                            ForEach(viewModel.unconfiguredServers) { server in
                                NavigationLink(value: server) {
                                    MCPServerRow(server: server, viewModel: viewModel, isDisabled: true)
                                }
                            }
                        } header: {
                            Text("Disabled")
                                .caption()
                                .foregroundColor(Color.foreground["300"])
                        }
                    }

                    if enabledServers.isEmpty && availableServers.isEmpty && viewModel.unconfiguredServers.isEmpty {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: "link.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("No MCP servers available")
                                    .headline()
                                Text("Check your server configuration or try refreshing")
                                    .caption()
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle("Tools & Integrations")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MCPServer.self) { server in
                MCPServerDetailView(server: server, viewModel: viewModel)
            }
            .task {
                setupAPIClient()
                Task {
                    await viewModel.loadServers()
                }
            }
            .sheet(isPresented: $showingAddServer) {
                AddCustomServerView(
                    viewModel: viewModel,
                    onServerAdded: {
                        await viewModel.loadServers()
                    }
                )
            }
        }
        .presentationDragIndicator(.visible)
        .withToastContainer()
    }

    private func setupAPIClient() {
        guard let baseURL = session.serverURL else {
            viewModel.errorMessage = "No server configured"
            return
        }

        guard session.deviceToken != nil else {
            viewModel.errorMessage = "Device not registered"
            return
        }

        guard session.userToken != nil else {
            viewModel.errorMessage = "User not authenticated"
            return
        }

        let apiClient = APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { session.deviceToken },
            userTokenProvider: { session.userToken }
        )
        viewModel.setAPIClient(apiClient)
    }
}

// MARK: - Server Row

struct MCPServerRow: View {
    let server: MCPServer
    let viewModel: MCPIntegrationsViewModel
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(server.name)
                .bodyLarge()
                .foregroundColor(isDisabled ? Color.foreground["300"] : Color.foreground["000"])

            if let description = server.description {
                Text(description)
                    .bodySmall()
                    .foregroundColor(Color.foreground["300"])
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Text("\(server.tools.count) tools")
                    .bodySmall()
                    .foregroundColor(Color.foreground["300"])

                statusIndicator
            }
            .padding(.top, 6)
        }
        .padding(.vertical, 4)
        .opacity(isDisabled ? 0.7 : 1.0)
    }

    /// Whether this server requires user authentication/connection
    private var requiresAuth: Bool {
        // URL-based servers don't need auth (authType is nil, already connected via URL)
        if server.authType == nil && server.type == .remote {
            return false
        }
        return (server.type != .local) || (server.connectionStrategy != nil)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            switch server.connectionStatus {
            case .connected, .authorized:
                Circle()
                    .fill(Color.semantic["success"])
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .caption()
                    .foregroundColor(Color.semantic["success"])
            case .available:
                // Available means configured by admin - but user may still need to connect
                if requiresAuth {
                    Circle()
                        .stroke(Color.foreground["300"], lineWidth: 1)
                        .frame(width: 6, height: 6)
                    Text("Not connected")
                        .caption()
                        .foregroundColor(Color.foreground["300"])
                } else {
                    Circle()
                        .fill(Color.semantic["success"])
                        .frame(width: 6, height: 6)
                    Text("Enabled")
                        .caption()
                        .foregroundColor(Color.semantic["success"])
                }
            case .notConnected, .disconnected:
                Circle()
                    .stroke(Color.foreground["300"], lineWidth: 1)
                    .frame(width: 6, height: 6)
                Text("Not connected")
                    .caption()
                    .foregroundColor(Color.foreground["300"])
            case .needsSetup:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.semantic["warning"])
                Text("Needs configuration")
                    .caption()
                    .foregroundColor(Color.semantic["warning"])
            case .expired, .revoked:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.semantic["warning"])
                Text("Reconnect required")
                    .caption()
                    .foregroundColor(Color.semantic["warning"])
            case .pending:
                ProgressView()
                    .scaleEffect(0.5)
                Text("Connecting...")
                    .caption()
                    .foregroundColor(Color.foreground["300"])
            }
        }
    }

    private var statusText: String {
        let connectionCount = viewModel.connections(for: server).count
        if server.connectionStrategy == "multiple" && connectionCount > 0 {
            return "\(connectionCount) \(connectionCount == 1 ? "account" : "accounts")"
        }
        return "Connected"
    }
}

// MARK: - Server Detail View

struct MCPServerDetailView: View {
    let server: MCPServer
    @Bindable var viewModel: MCPIntegrationsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var connections: [MCPConnectionInfo] = []
    @State private var isLoading = true
    @State private var isConnecting = false
    @State private var showingDeleteConfirmation = false
    @State private var connectionToDelete: MCPConnectionInfo?

    private var requiresAuth: Bool {
        // URL-based servers don't need auth (authType is nil, already connected via URL)
        if server.authType == nil && server.type == .remote {
            return false
        }
        return (server.type != .local) || (server.connectionStrategy != nil)
    }

    private var isConnected: Bool {
        server.connectionStatus == .connected ||
        server.connectionStatus == .authorized ||
        !connections.isEmpty  // Also check loaded connections (handles stale server state)
    }

    private var isMultiConnection: Bool {
        server.connectionStrategy == "multiple"
    }

    var body: some View {
        List {
            // Connection section (only for servers that require auth)
            if requiresAuth {
                Section {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else if isConnected && !connections.isEmpty {
                        // Show existing connections
                        ForEach(connections, id: \.id) { connection in
                            connectionRow(connection)
                        }

                        // Add account button for multi-connection servers
                        if isMultiConnection {
                            addConnectionButton
                        }
                    } else {
                        // Not connected - show connect prompt
                        connectPrompt
                    }
                }
            }

            // Description section
            if let description = server.description {
                Section {
                    Text(description)
                        .body()
                        .foregroundColor(Color.foreground["200"])
                }
            }

            // Tools section
            if !server.tools.isEmpty {
                Section {
                    ForEach(server.tools, id: \.self) { tool in
                        Text(tool)
                            .body()
                            .foregroundColor(Color.foreground["100"])
                    }
                } header: {
                    Text("\(server.tools.count) tools")
                        .titleSmall()
                        .foregroundColor(Color.foreground["000"])
                        .textCase(nil)
                }
            }

        }
        .listStyle(.insetGrouped)
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Disconnect?", isPresented: $showingDeleteConfirmation, presenting: connectionToDelete) { connection in
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task {
                    await disconnectConnection(connection)
                }
            }
        } message: { connection in
            Text("Are you sure you want to disconnect \(connection.label)?")
        }
        .task {
            if requiresAuth {
                await loadConnections()
            } else {
                isLoading = false
            }
        }
    }

    // MARK: - Connection Row

    private func connectionRow(_ connection: MCPConnectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connected with \(connection.label)")
                .body()
                .foregroundColor(Color.foreground["100"])

            if let date = parseDate(connection.createdAt) {
                Text("on \(date.formatted(date: .abbreviated, time: .omitted))")
                    .caption()
                    .foregroundColor(Color.foreground["300"])
            }

            Button(action: {
                connectionToDelete = connection
                showingDeleteConfirmation = true
            }) {
                Text("Disconnect")
                    .body()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.semantic["error"].opacity(0.1))
                    .foregroundColor(Color.semantic["error"])
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Connect Prompt

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect with your account to use this MCP server")
                .body()
                .foregroundColor(Color.foreground["200"])

            Button(action: {
                Task { await addConnection() }
            }) {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.semantic["success"])
                    }
                    Text(isConnecting ? "Connecting..." : "Connect")
                        .body()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.semantic["success"].opacity(0.1))
                .foregroundColor(Color.semantic["success"])
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Add Connection Button

    private var addConnectionButton: some View {
        Button(action: {
            Task { await addConnection() }
        }) {
            HStack {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Color.semantic["success"])
                }
                Text(isConnecting ? "Connecting..." : "Add Account")
                    .body()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.semantic["success"].opacity(0.1))
            .foregroundColor(Color.semantic["success"])
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func loadConnections() async {
        isLoading = true
        await viewModel.loadConnections(for: server.apiName)
        connections = viewModel.connections(for: server)
        isLoading = false
    }

    private func addConnection() async {
        print("🔐 MCPServerDetailView: addConnection called for \(server.name)")
        isConnecting = true

        do {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                print("❌ MCPServerDetailView: No view controller available")
                throw APIClient.APIError.requestFailed(statusCode: nil, message: "No view controller available")
            }

            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            print("🔐 MCPServerDetailView: Got top controller, server type: \(server.type)")

            switch server.type {
            case .remote, .defaultRemote:
                print("🔐 MCPServerDetailView: Calling connectRemoteWithWebAuth")
                try await viewModel.connectRemoteWithWebAuth(server: server, from: topController)
            case .local:
                print("🔐 MCPServerDetailView: Calling connectWithHandler")
                try await viewModel.connectWithHandler(server: server, from: topController)
            }

            print("✅ MCPServerDetailView: Connection successful")
            await loadConnections()
            await viewModel.loadServers()  // Refresh server list for parent view
        } catch {
            print("❌ MCPServerDetailView: Error - \(error)")
            // Don't show error for user cancellation
            if case MCPOAuthError.userCancelled = error {
                print("🔐 MCPServerDetailView: User cancelled")
                // Silent - user cancelled intentionally
            } else {
                print("🔐 MCPServerDetailView: Showing toast for error: \(error.localizedDescription)")
                ToastManager.shared.show(error.localizedDescription, type: .error)
            }
        }

        isConnecting = false
        print("🔐 MCPServerDetailView: addConnection finished")
    }

    private func disconnectConnection(_ connection: MCPConnectionInfo) async {
        do {
            try await viewModel.disconnectConnection(connection.id, serverName: server.apiName)
            await loadConnections()
            await viewModel.loadServers()  // Refresh server list for parent view
        } catch {
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}

#Preview {
    MCPIntegrationsView()
        .environment(SessionManager())
}
