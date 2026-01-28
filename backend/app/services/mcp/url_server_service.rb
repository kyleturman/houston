# frozen_string_literal: true

module Mcp
  # Service for handling custom MCP servers added by users.
  # Supports both URL-based servers (no auth) and OAuth servers.
  # All server data is stored in UserMcpConnection with remote_server_config in metadata.
  class UrlServerService
    class << self
      # Delegate slugification to McpServer which includes Slugifiable
      def slugify(name)
        McpServer.slugify(name)
      end

      # Unified add server flow with auto-detection
      # Discovers auth requirements and either connects directly or creates OAuth server record
      # @param user [User] The user adding the server
      # @param name [String] User-provided server name
      # @param url [String] The MCP server URL
      # @return [Hash] { success: bool, action: :enabled|:available, ... }
      def add_server(user:, name:, url:)
        Rails.logger.info("[UrlServerService] Adding server '#{name}' at #{url}")

        slug = slugify(name)

        # Check for duplicate names
        if server_name_exists?(user, slug)
          return { success: false, error: "A server with a similar name already exists. Please choose a different name." }
        end

        # First, discover what auth the server needs
        discovery = ServerDiscoveryService.discover(url)

        if discovery.success?
          # No auth needed - connect directly and add to enabled
          Rails.logger.info("[UrlServerService] Server '#{name}' requires no auth, connecting directly")
          result = connect(user: user, server_name: name, url: url)

          if result[:success]
            {
              success: true,
              action: :enabled,
              connection: result[:connection],
              tools_count: result[:tools_count],
              display_name: result[:display_name]
            }
          else
            { success: false, error: result[:error] }
          end
        elsif discovery.needs_auth? && discovery.auth_type == :oauth
          # OAuth available - create pending connection, return as "available"
          Rails.logger.info("[UrlServerService] Server '#{name}' requires OAuth, creating pending connection")
          create_oauth_server(user: user, name: name, url: url, oauth_metadata: discovery.oauth_metadata)
        elsif discovery.needs_auth?
          # Unknown auth type - could be API key or other
          Rails.logger.info("[UrlServerService] Server '#{name}' requires unknown auth type")
          { success: false, error: 'Server requires authentication but OAuth discovery failed. Please check the URL or contact the server administrator.' }
        else
          # Error during discovery
          { success: false, error: discovery.error || 'Could not connect to server. Please check the URL is correct.' }
        end
      rescue StandardError => e
        Rails.logger.error("[UrlServerService] add_server failed: #{e.message}")
        { success: false, error: e.message }
      end

      # Connect to a URL-based MCP server (no auth needed)
      # Creates UserMcpConnection with remote_server_config and URL in credentials
      def connect(user:, server_name:, url:)
        slug = slugify(server_name)

        # Create user connection with remote_server_config and URL
        connection = find_or_create_connection(user, slug, server_name, url, 'direct')
        connection.credentials = { 'url' => url }.to_json
        connection.status = 'pending'
        connection.save!

        # Fetch tools from the server
        tools = fetch_tools_via_http(url)

        if tools.present?
          formatted_tools = tools.map { |t| { 'name' => t['name'], 'description' => t['description'] || '', 'input_schema' => t['inputSchema'] } }

          connection.tools_cache = formatted_tools
          connection.touch_last_connected
          connection.clear_error
          connection.status = 'active'
          connection.save!

          # Also register in McpServer for the agent to use
          register_mcp_server(slug, url, tools, server_name)

          { success: true, connection: connection, tools_count: tools.size, display_name: server_name }
        else
          # Clean up failed connection - don't leave orphaned records
          connection.destroy
          { success: false, error: 'Could not connect to server. Please check the URL is correct.' }
        end
      rescue StandardError => e
        Rails.logger.error("[UrlServerService] Connect failed: #{e.message}")
        # Clean up failed connection - don't leave orphaned records
        connection&.destroy
        { success: false, error: e.message }
      end

      # Disconnect a URL-based server
      def disconnect(user:, server_name:)
        slug = slugify(server_name)
        connection = find_connection_by_name(user, slug)

        return { success: false, error: 'Server not found' } unless connection

        connection.destroy!

        # Clean up McpServer if this was the last connection
        remaining = UserMcpConnection.remote_connections.where.not(user: user).select { |c| c.server_name == slug }
        if remaining.empty?
          McpServer.where(name: slug).destroy_all
        end

        { success: true }
      rescue StandardError => e
        Rails.logger.error("[UrlServerService] Disconnect failed: #{e.message}")
        { success: false, error: e.message }
      end

      # Get status of a URL-based server
      def status(user:, server_name:)
        slug = slugify(server_name)
        connection = find_connection_by_name(user, slug)

        return { connected: false, status: 'not_found' } unless connection

        {
          connected: connection.active? || connection.authorized?,
          status: connection.status,
          tools_count: connection.tools_cache&.size || 0,
          last_connected_at: connection.last_connected_at,
          error_message: connection.error_message
        }
      end

      private

      # Check if a server name already exists (in defaults or user's connections)
      # Only blocks if an active/authorized connection exists - disconnected ones can be reconnected
      def server_name_exists?(user, slug)
        # Check defaults
        return true if DefaultServersService.instance.default_server?(slug)

        # Check local MCP servers (but not remote ones - those are user-added)
        return true if McpServer.where(name: slug).where.not("metadata->>'kind' = ?", 'remote').exists?

        # Check user's existing active connections (disconnected ones can be reconnected)
        user.user_mcp_connections.remote_connections.any? { |c| c.server_name == slug && (c.active? || c.authorized?) }
      end

      # Find existing connection by server name
      def find_connection_by_name(user, slug)
        user.user_mcp_connections.remote_connections.find { |c| c.server_name == slug }
      end

      # Find or create connection with remote_server_config
      # If a disconnected connection exists, update its config for reconnection
      def find_or_create_connection(user, slug, display_name, url, auth_type)
        existing = find_connection_by_name(user, slug)

        if existing
          # Update config for reconnection (handles case where old connection had empty config)
          existing.remote_server_config = {
            'name' => slug,
            'display_name' => display_name,
            'url' => url,
            'auth_type' => auth_type,
            'source' => 'user_added',
            'added_at' => Time.current.iso8601
          }
          return existing
        end

        user.user_mcp_connections.new(
          metadata: {
            'remote_server_config' => {
              'name' => slug,
              'display_name' => display_name,
              'url' => url,
              'auth_type' => auth_type,
              'source' => 'user_added',
              'added_at' => Time.current.iso8601
            }
          }
        )
      end

      # Fetch tools via HTTP transport (Streamable HTTP)
      def fetch_tools_via_http(url)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json, text/event-stream'
        request.body = {
          jsonrpc: '2.0',
          id: SecureRandom.uuid,
          method: 'tools/list',
          params: {}
        }.to_json

        response = http.request(request)

        return nil unless response.is_a?(Net::HTTPSuccess)

        data = Mcp::ResponseParser.parse(response.body.to_s, context: "[UrlServerService]")
        data&.dig('result', 'tools')
      rescue StandardError => e
        Rails.logger.warn("[UrlServerService] HTTP fetch failed: #{e.message}")
        nil
      end

      # Create a pending connection for OAuth-based servers
      def create_oauth_server(user:, name:, url:, oauth_metadata:)
        slug = slugify(name)

        # Create pending connection with OAuth metadata
        connection = find_or_create_connection(user, slug, name, url, 'oauth_consent')

        # Store OAuth metadata for later use
        remote_server_config = connection.remote_server_config
        remote_server_config['oauth_metadata'] = oauth_metadata
        connection.remote_server_config = remote_server_config
        connection.status = 'pending'
        connection.save!

        # Also register in McpServer (without tools for now - will be fetched after OAuth)
        mcp_server = McpServer.find_or_initialize_by(name: slug)
        mcp_server.assign_attributes(
          transport: 'http',
          endpoint: url,
          healthy: false, # Not healthy until authenticated
          metadata: {
            'kind' => 'remote',
            'display_name' => name,
            'category' => 'Custom',
            'auth_type' => 'oauth_consent',
            'user_added' => true
          }
        )
        mcp_server.save!

        {
          success: true,
          action: :available,
          connection_id: connection.id,
          server_name: slug,
          needs_auth: true,
          auth_type: 'oauth_consent'
        }
      end

      # Register the server in McpServer so agents can use the tools
      # @param slug [String] URL-safe identifier (e.g., "lastfm")
      # @param url [String] Server endpoint URL
      # @param tools [Array] List of tools from the server
      # @param display_name [String] Human-readable name (e.g., "Last.fm")
      def register_mcp_server(slug, url, tools, display_name)
        mcp_server = McpServer.find_or_initialize_by(name: slug)
        mcp_server.assign_attributes(
          transport: 'http',
          endpoint: url,  # Store actual URL so tools can be called
          healthy: true,
          last_seen_at: Time.current,
          tools_cache: tools.map { |t| { 'name' => t['name'], 'description' => t['description'] || '', 'input_schema' => t['inputSchema'] } },
          metadata: {
            'kind' => 'remote',  # Mark as remote so it shows in remote servers list
            'display_name' => display_name,
            'category' => 'Custom'
          }
        )
        mcp_server.save!

        # Also register in ConnectionManager so tools can be called immediately
        Mcp::ConnectionManager.instance.register_remote_server(slug, url, { 'kind' => 'remote' })
      end
    end
  end
end
