import Foundation

// MARK: - MCP Server API Models
//
// Models for Model Context Protocol (MCP) server integrations.
// Supports local, remote, and custom MCP servers with various auth methods.

// MARK: - Server List Response

/// Response containing lists of available MCP servers
struct MCPServersResponse: Decodable {
    let servers: [MCPServer]
    let localServers: [MCPServer]?
    let unconfiguredServers: [MCPServer]?
    let remoteServers: [MCPServer]?
    let localCount: Int
    let remoteCount: Int
    let unconfiguredCount: Int?

    enum CodingKeys: String, CodingKey {
        case servers
        case localServers = "local_servers"
        case unconfiguredServers = "unconfigured_servers"
        case remoteServers = "remote_servers"
        case localCount = "local_count"
        case remoteCount = "remote_count"
        case unconfiguredCount = "unconfigured_count"
    }
}

// MARK: - Server Model

/// MCP server configuration
struct MCPServer: Decodable, Identifiable, Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MCPServer, rhs: MCPServer) -> Bool {
        lhs.id == rhs.id
    }

    let id: String
    let name: String
    let internalName: String?
    let type: MCPServerType
    let description: String?
    let baseUrl: String?
    let authType: String?
    let connectionStatus: MCPConnectionStatus
    let connectionStrategy: String?
    let endpoint: String?
    let healthy: Bool?
    let tools: [String]
    let expiresAt: Date?
    let needsRefresh: Bool?
    let configurationStatus: ConfigurationStatus?
    let enabled: Bool?
    let configured: Bool?

    /// Name to use for API calls - uses internalName if available, otherwise name
    var apiName: String {
        return internalName ?? name
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, description, endpoint, healthy, tools, enabled, configured
        case internalName = "internal_name"
        case baseUrl = "base_url"
        case authType = "auth_type"
        case connectionStatus = "connection_status"
        case connectionStrategy = "connection_strategy"
        case expiresAt = "expires_at"
        case needsRefresh = "needs_refresh"
        case configurationStatus = "configuration_status"
    }

    /// Check if this server uses API key auth (which needs a text field)
    var usesApiKeyAuth: Bool {
        return authType == "api_key"
    }

    /// Check if server needs admin setup
    var needsSetup: Bool {
        return connectionStatus == .needsSetup || configured == false
    }
}

// MARK: - Server Type & Status

/// Type of MCP server
enum MCPServerType: String, Decodable {
    case local = "local"
    case remote = "remote"
    case defaultRemote = "default_remote"
}

/// Connection status for an MCP server
enum MCPConnectionStatus: String, Decodable {
    case connected = "connected"
    case disconnected = "disconnected"
    case authorized = "authorized"
    case notConnected = "not_connected"
    case available = "available"
    case expired = "expired"
    case pending = "pending"
    case revoked = "revoked"
    case needsSetup = "needs_setup"
}

/// Configuration status for an MCP server
struct ConfigurationStatus: Decodable {
    let configured: Bool
    let authType: String?
    let missing: [String]?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case configured
        case authType = "auth_type"
        case missing
        case message
    }
}

// MARK: - Connection Responses

/// Response from connecting to an MCP server
struct MCPConnectionResponse: Decodable {
    let type: String
    let authorizeUrl: String?
    let serverName: String
    let serverId: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case type, status
        case authorizeUrl = "authorize_url"
        case serverName = "server_name"
        case serverId = "server_id"
    }
}

// MARK: - Auth Responses

/// Response from initiating MCP authentication
struct MCPAuthInitiateResponse: Decodable {
    let success: Bool
    let type: String
    let handler: String?
    let linkToken: String?
    let expiration: String?
    let fields: [MCPField]?
    let iosConfig: [String: AnyCodable]?

    struct MCPField: Decodable {
        let key: String
        let label: String
        let placeholder: String?
        let secure: Bool
    }

    enum CodingKeys: String, CodingKey {
        case success, type, handler, linkToken, expiration, fields
        case iosConfig = "iosConfig"
    }
}

/// Information about an MCP connection
struct MCPConnectionInfo: Decodable {
    let id: Int
    let serverName: String
    let label: String
    let institutionName: String?
    let accountCount: Int
    let status: String
    let metadata: [String: JSONValue]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, serverName, label, institutionName, accountCount, status, metadata, createdAt
    }
}

/// Response containing list of MCP connections
struct MCPConnectionsListResponse: Decodable {
    let success: Bool
    let connections: [MCPConnectionInfo]
}

/// Response from creating an MCP connection
struct MCPConnectionCreateResponse: Decodable {
    let success: Bool
    let connection: MCPConnectionInfo
}

/// Response for MCP server status
struct MCPStatusResponse: Decodable {
    let success: Bool
    let connected: Bool
    let connectionCount: Int
    let connections: [MCPConnectionInfo]

    enum CodingKeys: String, CodingKey {
        case success, connected, connectionCount, connections
    }
}

// MARK: - Custom Server Responses

/// Response from adding a custom server
struct AddServerResponse: Decodable {
    let success: Bool
    let status: String?
    let serverId: Int?
    let serverName: String?
    let needsAuth: Bool?
    let authType: String?
    let toolsCount: Int?
    let displayName: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, status, error
        case serverId = "server_id"
        case serverName = "server_name"
        case needsAuth = "needs_auth"
        case authType = "auth_type"
        case toolsCount = "tools_count"
        case displayName = "display_name"
    }
}

/// Response for custom server status
struct CustomServerStatusResponse: Decodable {
    let success: Bool
    let connected: Bool
    let status: String?
    let toolsCount: Int?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case success, connected, status
        case toolsCount = "tools_count"
        case errorMessage = "error_message"
    }
}
