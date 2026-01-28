# frozen_string_literal: true

module Mcp
  # Generic authentication service for MCP servers
  # Handles initiation, token exchange, and disconnection for any MCP server
  class AuthService
    class AuthError < StandardError; end

    class << self
      # Initiate auth flow for a server
      # @param server_name [String] Name of the MCP server
      # @param user [User] The user initiating auth
      # @param redirect_uri [String] Optional redirect URI (for mobile)
      # @return [Hash] Auth initiation response (depends on provider type)
      def initiate(server_name:, user:, redirect_uri: nil)
        server = find_server(server_name)
        provider = load_provider(server)

        provider.initiate(user: user, redirect_uri: redirect_uri)
      end

      # Exchange credentials for access token
      # @param server_name [String] Name of the MCP server
      # @param user [User] The user exchanging credentials
      # @param credentials [Hash] Provider-specific credentials
      # @param metadata [Hash] Optional metadata
      # @return [UserMcpConnection] The created connection
      def exchange(server_name:, user:, credentials:, metadata: {})
        server = find_server(server_name)
        provider = load_provider(server)

        # Pass credentials and metadata separately to provider
        result = provider.exchange(user: user, credentials: credentials, metadata: metadata)

        # Use metadata from provider result (which may have merged client metadata)
        merged_metadata = result[:metadata] || {}

        # Create connection
        connection_id = result[:connection_identifier] || SecureRandom.uuid

        user.user_mcp_connections.create!(
          mcp_server: server,
          connection_identifier: connection_id,
          credentials: result[:credentials].to_json,
          metadata: merged_metadata,
          status: :active
        )
      end

      # Disconnect a connection
      # @param connection_id [Integer] UserMcpConnection ID
      # @param user [User] The user
      def disconnect(connection_id:, user:)
        connection = user.user_mcp_connections.find(connection_id)

        # For local MCP servers, call the provider's disconnect if available
        if connection.mcp_server
          provider = load_provider(connection.mcp_server)
          provider.disconnect(connection: connection) if provider.respond_to?(:disconnect)
        end

        # For remote MCP servers, just clear credentials
        if connection.remote_mcp_server
          connection.update!(
            status: :disconnected,
            credentials: nil,
            refresh_token: nil,
            expires_at: nil
          )
        else
          connection.update!(status: :disconnected)
        end
      end

      # Get connections for a server
      # @param server_name [String] Name of the MCP server
      # @param user [User] The user
      # @return [Array<UserMcpConnection>] Active connections
      def connections_for(server_name:, user:)
        # Try local server first
        server = find_server(server_name) rescue nil

        if server
          # Check if this is a remote MCP server entry (has kind=remote in metadata)
          if server.remote?
            # Find the RemoteMcpServer by name and return connections for it
            remote_server = RemoteMcpServer.find_by(name: server.name)
            if remote_server
              return user.user_mcp_connections
                .where(remote_mcp_server: remote_server)
                .active_connections
                .order(created_at: :desc)
            end
          end

          # Local server - return connections for mcp_server
          return user.user_mcp_connections
            .where(mcp_server: server)
            .active_connections
            .order(created_at: :desc)
        end

        # Try finding as RemoteMcpServer directly by name (names are slugified)
        remote_server = RemoteMcpServer.find_by(name: server_name.to_s.downcase)
        if remote_server
          return user.user_mcp_connections
            .where(remote_mcp_server: remote_server)
            .active_connections
            .order(created_at: :desc)
        end

        raise AuthError, "MCP server '#{server_name}' not found"
      end

      # Get connection status for a server
      # @param server_name [String] Name of the MCP server
      # @param user [User] The user
      # @return [Hash] Connection status info
      def status(server_name:, user:)
        connections = connections_for(server_name: server_name, user: user)
        has_connection = connections.any?

        {
          connected: has_connection,
          connection_count: connections.size,
          connections: connections.map { |c| connection_info(c) }
        }
      end

      private

      def find_server(server_name)
        # Names are slugified, so we can do direct lookup; also check display name for UI lookups
        McpServer.find_by(name: server_name.to_s.downcase) ||
          McpServer.all.find { |s| s.display_name&.downcase == server_name.to_s.downcase } ||
          raise(AuthError, "MCP server '#{server_name}' not found")
      end

      def load_provider(server)
        config = server.auth_provider_config
        raise AuthError, "No auth provider configured for #{server.name}" if config.nil?

        provider_type = config['type']
        provider_class = case provider_type
                         when 'plaid_link' then AuthProviders::PlaidLink
                         when 'oauth2' then AuthProviders::OAuth2 rescue nil
                         when 'api_key' then AuthProviders::ApiKey
                         when 'none' then raise AuthError, "Server #{server.name} does not require authentication"
                         else raise AuthError, "Unknown auth provider type: #{provider_type}"
                         end

        raise AuthError, "Provider class not found for #{provider_type}" if provider_class.nil?

        provider_class.new(config, server)
      end

      def connection_info(connection)
        {
          id: connection.id,
          label: connection.display_label,
          institution_name: connection.institution_name,
          account_count: connection.accounts.size,
          status: connection.status,
          created_at: connection.created_at
        }
      end
    end
  end
end
