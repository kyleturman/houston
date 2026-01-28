import Foundation
import SafariServices
import UIKit
import Observation

@MainActor
@Observable
class MCPIntegrationsViewModel {
    var localServers: [MCPServer] = []
    var remoteServers: [MCPServer] = []
    var defaultServers: [MCPServer] = []
    var unconfiguredServers: [MCPServer] = []
    var loading = false
    var errorMessage: String?
    var serverConnections: [String: [MCPConnectionInfo]] = [:] // serverName -> connections

    private(set) var apiClient: APIClient?

    func setAPIClient(_ client: APIClient) {
        self.apiClient = client
    }

    func loadServers() async {
        guard let apiClient = apiClient else {
            errorMessage = "API client not initialized"
            return
        }

        loading = true
        errorMessage = nil

        do {
            print("MCPIntegrationsViewModel: Loading servers...")
            let serversResponse = try await apiClient.listMCPServers()
            print("MCPIntegrationsViewModel: Received \(serversResponse.servers.count) servers")

            // Use server groupings from response if available
            if let local = serversResponse.localServers {
                localServers = local
            } else {
                localServers = serversResponse.servers.filter { $0.type == .local && $0.configured != false }
            }

            if let unconfigured = serversResponse.unconfiguredServers {
                unconfiguredServers = unconfigured
            } else {
                unconfiguredServers = serversResponse.servers.filter { $0.connectionStatus == .needsSetup || $0.configured == false }
            }

            if let remote = serversResponse.remoteServers {
                remoteServers = remote
            } else {
                remoteServers = serversResponse.servers.filter { $0.type == .remote }
            }

            // Keep defaultServers for backwards compatibility
            defaultServers = serversResponse.servers.filter { $0.type == .defaultRemote }

            print("MCPIntegrationsViewModel: Local: \(localServers.count), Remote: \(remoteServers.count), Default: \(defaultServers.count), Unconfigured: \(unconfiguredServers.count)")

        } catch {
            print("MCPIntegrationsViewModel: Error loading servers: \(error)")
            errorMessage = error.localizedDescription
        }

        loading = false
    }
    
    func connectWithApiKey(server: MCPServer, apiKey: String) async throws {
        guard let apiClient = apiClient else { return }
        
        _ = try await apiClient.connectMCPServerWithApiKey(serverId: server.id, apiKey: apiKey)
        
        // Reload servers to get updated connection status
        await loadServers()
    }
    
    func connectWithOAuth(server: MCPServer) async throws {
        guard let apiClient = apiClient else { return }

        let connectionResponse = try await apiClient.connectMCPServerWithOAuth(serverId: server.id)

        guard let authorizeUrl = connectionResponse.authorizeUrl,
              let url = URL(string: authorizeUrl) else {
            throw APIClient.APIError.requestFailed(statusCode: nil, message: "Invalid or missing authorize URL")
        }

        // Open Safari for OAuth flow
        await openOAuthURL(url)
    }

    /// Connect to a remote MCP server using ASWebAuthenticationSession
    /// This provides a better UX than SFSafariViewController for OAuth flows
    func connectRemoteWithWebAuth(
        server: MCPServer,
        from viewController: UIViewController
    ) async throws {
        guard let apiClient = apiClient else {
            throw APIClient.APIError.requestFailed(statusCode: nil, message: "API client not initialized")
        }

        // Get the authorization URL from the backend
        let connectionResponse = try await apiClient.connectMCPServerWithOAuth(serverId: server.id)

        guard let authorizeUrl = connectionResponse.authorizeUrl else {
            throw APIClient.APIError.requestFailed(statusCode: nil, message: "Invalid or missing authorize URL")
        }

        // Use the WebAuth OAuth handler
        guard let handler = MCPOAuthHandlerRegistry.shared.handler(for: "oauth2") else {
            throw MCPOAuthError.handlerNotFound("oauth2")
        }

        // Present OAuth flow
        return try await withCheckedThrowingContinuation { continuation in
            handler.present(
                linkToken: authorizeUrl,
                config: nil,
                from: viewController
            ) { result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        // OAuth complete - reload servers to get updated status
                        await self.loadServers()
                        continuation.resume(returning: ())
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func disconnect(server: MCPServer) async throws {
        guard let apiClient = apiClient else { return }

        _ = try await apiClient.disconnectMCPServer(serverId: server.id)

        // Reload servers to get updated connection status
        await loadServers()
    }

    private func openOAuthURL(_ url: URL) async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let safariViewController = SFSafariViewController(url: url)
        safariViewController.modalPresentationStyle = .pageSheet

        rootViewController.present(safariViewController, animated: true)
    }

    // MARK: - New Modular Connection Methods

    /// Connect to an MCP server using the appropriate OAuth handler
    func connectWithHandler(
        server: MCPServer,
        from viewController: UIViewController
    ) async throws {
        print("🔐 MCPIntegrationsViewModel: connectWithHandler called for \(server.apiName)")
        guard let apiClient = apiClient else {
            print("❌ MCPIntegrationsViewModel: API client not initialized")
            throw APIClient.APIError.requestFailed(statusCode: nil, message: "API client not initialized")
        }

        // Initiate auth flow - use apiName for URL-safe internal name
        print("🔐 MCPIntegrationsViewModel: Calling initiateMCPAuth for \(server.apiName)")
        let authResponse = try await apiClient.initiateMCPAuth(serverName: server.apiName)
        print("🔐 MCPIntegrationsViewModel: Got auth response - handler: \(authResponse.handler ?? "nil"), linkToken: \(authResponse.linkToken != nil ? "present" : "nil")")

        guard let linkToken = authResponse.linkToken else {
            print("❌ MCPIntegrationsViewModel: No link token received")
            throw APIClient.APIError.requestFailed(statusCode: nil, message: "No link token received")
        }

        // Get the handler type (defaults to "oauth2" if not specified)
        let handlerType = authResponse.handler ?? "oauth2"
        print("🔐 MCPIntegrationsViewModel: Using handler type: \(handlerType)")

        // Look up the handler in the registry
        guard let handler = MCPOAuthHandlerRegistry.shared.handler(for: handlerType) else {
            print("❌ MCPIntegrationsViewModel: Handler not found for type: \(handlerType)")
            throw MCPOAuthError.handlerNotFound(handlerType)
        }
        print("🔐 MCPIntegrationsViewModel: Found handler, presenting OAuth flow...")

        // Convert iosConfig to [String: Any]
        var config: [String: Any]? = nil
        if let iosConfig = authResponse.iosConfig {
            config = iosConfig.mapValues { $0.value }
        }

        // Present the OAuth flow using the handler
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            handler.present(
                linkToken: linkToken,
                config: config,
                from: viewController
            ) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let (publicToken, metadata)):
                        do {
                            // Check if server already exchanged the token (oauth_complete means server-side exchange done)
                            if publicToken == "oauth_complete" {
                                print("🔐 MCPIntegrationsViewModel: Server-side OAuth complete, skipping client exchange")
                                // Server already exchanged tokens - just load connections
                                await self.loadConnections(for: server.apiName)
                                continuation.resume()
                                return
                            }

                            // Build credentials based on auth type
                            var credentials: [String: Any] = [:]
                            if metadata["type"] as? String == "authorization_code" {
                                // OAuth2 flow - send authorization code
                                credentials["code"] = publicToken
                                if let state = metadata["state"] as? String {
                                    credentials["state"] = state
                                }
                                if let redirectUri = config?["redirectUri"] as? String {
                                    credentials["redirect_uri"] = redirectUri
                                }
                            } else {
                                // Plaid or other flow - send public token
                                credentials["public_token"] = publicToken
                            }

                            // Exchange the token for a connection
                            _ = try await apiClient.exchangeMCPToken(
                                serverName: server.apiName,
                                credentials: credentials,
                                metadata: metadata
                            )

                            // Load connections for this server
                            await self.loadConnections(for: server.apiName)

                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }

                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Load all connections for a specific server
    func loadConnections(for serverName: String) async {
        guard let apiClient = apiClient else { return }

        do {
            let connections = try await apiClient.getMCPConnections(serverName: serverName)
            // Create a new dictionary to trigger @Published change detection
            var updatedConnections = serverConnections
            updatedConnections[serverName] = connections
            serverConnections = updatedConnections
        } catch {
            print("Error loading connections for \(serverName): \(error)")
        }
    }

    /// Disconnect a specific connection
    func disconnectConnection(_ connectionId: Int, serverName: String) async throws {
        guard let apiClient = apiClient else { return }

        try await apiClient.disconnectMCPConnection(connectionId: connectionId)

        // Reload connections for this server
        await loadConnections(for: serverName)

        // Note: We don't reload servers here to avoid dismissing/reopening sheets
        // The server list will refresh when the user navigates back
    }

    /// Get connections for a server
    func connections(for server: MCPServer) -> [MCPConnectionInfo] {
        return serverConnections[server.apiName] ?? []
    }
}
