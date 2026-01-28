# frozen_string_literal: true

require 'net/http'
require 'json'

module Mcp
  class RemoteOauthService
    class DiscoveryError < StandardError; end
    class RegistrationError < StandardError; end

    class << self
      # Discover OAuth metadata from a remote MCP server
      # @param base_url [String] The MCP server URL (e.g., https://mcp.notion.com/sse)
      # @return [Hash] OAuth metadata including authorization and token endpoints
      def discover_oauth_metadata(base_url)
        # Extract base URL (remove /sse or /mcp path)
        uri = URI(base_url)
        server_base = "#{uri.scheme}://#{uri.host}"

        # Step 1: Fetch protected resource metadata
        resource_metadata = fetch_json("#{server_base}/.well-known/oauth-protected-resource")
        raise DiscoveryError, "Could not fetch resource metadata from #{server_base}" unless resource_metadata

        # Get authorization server URL
        auth_servers = resource_metadata['authorization_servers'] || [server_base]
        auth_server = auth_servers.first

        # Step 2: Fetch authorization server metadata
        auth_metadata = fetch_json("#{auth_server}/.well-known/oauth-authorization-server")
        raise DiscoveryError, "Could not fetch auth server metadata from #{auth_server}" unless auth_metadata

        {
          'resource_server' => server_base,
          'authorization_server' => auth_server,
          'authorize_url' => auth_metadata['authorization_endpoint'],
          'token_url' => auth_metadata['token_endpoint'],
          'registration_url' => auth_metadata['registration_endpoint'],
          'revocation_url' => auth_metadata['revocation_endpoint'],
          'response_types_supported' => auth_metadata['response_types_supported'],
          'grant_types_supported' => auth_metadata['grant_types_supported'],
          'code_challenge_methods_supported' => auth_metadata['code_challenge_methods_supported'],
          'token_endpoint_auth_methods_supported' => auth_metadata['token_endpoint_auth_methods_supported']
        }
      end

      # Dynamically register a client with the MCP server
      # @param oauth_metadata [Hash] OAuth metadata from discover_oauth_metadata
      # @param redirect_uri [String] The callback URL for our app
      # @return [Hash] Client credentials (client_id, client_secret if provided)
      def register_client(oauth_metadata, redirect_uri, client_name: 'Life Assistant')
        registration_url = oauth_metadata['registration_url']
        raise RegistrationError, "Registration endpoint not available" unless registration_url

        registration_data = {
          client_name: client_name,
          redirect_uris: [redirect_uri],
          grant_types: ['authorization_code', 'refresh_token'],
          response_types: ['code'],
          token_endpoint_auth_method: 'none' # For public clients (mobile apps)
        }

        response = post_json(registration_url, registration_data)
        raise RegistrationError, "Registration failed: #{response['error']}" if response['error']

        {
          'client_id' => response['client_id'],
          'client_secret' => response['client_secret'],
          'client_id_issued_at' => response['client_id_issued_at'],
          'client_secret_expires_at' => response['client_secret_expires_at']
        }
      end

      # Build OAuth authorization URL for a remote MCP server
      # This handles the full OAuth 2.1 flow with PKCE
      # @param server_info [Hash] Server info hash with :name, :url, :connection, :default_config (optional)
      def build_authorize_url_for_remote_mcp(server_info, redirect_uri, user, client_redirect_uri: nil)
        server_url = server_info[:url]
        server_name = server_info[:name]

        # Find or create connection
        connection = server_info[:connection] || find_or_create_connection(user, server_info)

        # Get or discover OAuth metadata
        oauth_metadata = connection.remote_server_config['oauth_metadata']

        if oauth_metadata.blank?
          Rails.logger.info("[MCP] Discovering OAuth metadata for #{server_name}...")
          oauth_metadata = discover_oauth_metadata(server_url)

          # Store discovered metadata in connection
          update_remote_server_config(connection, 'oauth_metadata', oauth_metadata)
        end

        # Check if we have client credentials, if not, register
        client_credentials = connection.remote_server_config['client_credentials']

        if client_credentials.blank? && oauth_metadata['registration_url'].present?
          Rails.logger.info("[MCP] Registering client with #{server_name}...")
          client_credentials = register_client(oauth_metadata, redirect_uri)

          # Store client credentials in connection
          update_remote_server_config(connection, 'client_credentials', client_credentials)
        end

        raise DiscoveryError, "No client credentials available" if client_credentials.blank?

        # Generate PKCE
        pkce_data = Mcp::OauthService.generate_pkce_pair
        state = Mcp::OauthService.generate_state

        # Update connection with OAuth state
        connection.update!(
          status: 'pending',
          state: state,
          code_verifier: pkce_data[:code_verifier],
          metadata: (connection.metadata || {}).merge(
            'redirect_uri' => redirect_uri,
            'client_redirect_uri' => client_redirect_uri
          ).compact
        )

        # Build authorization URL
        params = {
          response_type: 'code',
          client_id: client_credentials['client_id'],
          redirect_uri: redirect_uri,
          state: state,
          code_challenge: pkce_data[:code_challenge],
          code_challenge_method: pkce_data[:code_challenge_method]
        }

        uri = URI(oauth_metadata['authorize_url'])
        uri.query = URI.encode_www_form(params)
        uri.to_s
      end

      # Exchange authorization code for tokens (for remote MCP servers)
      # @param connection [UserMcpConnection] The connection record (found by state)
      # @param code [String] Authorization code
      def exchange_code_for_tokens_for_connection(connection, code)
        oauth_metadata = connection.remote_server_config['oauth_metadata']
        client_credentials = connection.remote_server_config['client_credentials']

        raise ArgumentError, "OAuth metadata missing" unless oauth_metadata
        raise ArgumentError, "Client credentials missing" unless client_credentials

        # Prepare token request
        token_params = {
          grant_type: 'authorization_code',
          client_id: client_credentials['client_id'],
          code: code,
          redirect_uri: connection.metadata&.dig('redirect_uri'),
          code_verifier: connection.code_verifier
        }

        # Make token request
        response = post_form(oauth_metadata['token_url'], token_params)

        if response['error']
          raise StandardError, "OAuth error: #{response['error']} - #{response['error_description']}"
        end

        access_token = response['access_token']

        # Extract any extra info from token response (some providers include workspace/user info)
        # Common fields: workspace_name, workspace_id, owner, bot_id, team, etc.
        token_response_info = response.except(
          'access_token', 'refresh_token', 'token_type', 'expires_in', 'scope'
        )

        # Set connection identifier from OAuth response for multi-account support
        # This extracts workspace_id, team_id, etc. to allow multiple accounts per server
        connection.set_connection_identifier_from_oauth(token_response_info) if token_response_info.present?

        # Update connection with tokens
        connection.update!(
          credentials: { 'access_token' => access_token }.to_json,
          refresh_token: response['refresh_token'],
          expires_at: response['expires_in'] ? Time.current + response['expires_in'].to_i.seconds : nil,
          status: 'authorized',
          metadata: connection.metadata.merge(
            'token_type' => response['token_type'] || 'Bearer',
            'scope' => response['scope'],
            'token_response_info' => token_response_info.presence
          ).compact,
          code_verifier: nil,
          state: nil
        )

        # Try to fetch and cache tools from the remote server
        fetch_and_cache_tools_for_connection(connection, access_token)

        connection
      end

      # Legacy method for backward compatibility during migration
      def exchange_code_for_tokens(remote_server, code, state, user)
        # Find connection by state
        connection = UserMcpConnection.find_by(
          user: user,
          remote_mcp_server: remote_server,
          state: state,
          status: 'pending'
        )

        raise ArgumentError, "Invalid state or connection not found" unless connection

        # Get OAuth metadata from remote_server (legacy) or connection
        oauth_metadata = connection.remote_server_config['oauth_metadata'] ||
                        remote_server.metadata&.dig('oauth_metadata')
        client_credentials = connection.remote_server_config['client_credentials'] ||
                            remote_server.metadata&.dig('client_credentials')

        raise ArgumentError, "OAuth metadata missing" unless oauth_metadata
        raise ArgumentError, "Client credentials missing" unless client_credentials

        # Store in connection if not already there
        if connection.remote_server_config['oauth_metadata'].blank?
          update_remote_server_config(connection, 'oauth_metadata', oauth_metadata)
        end
        if connection.remote_server_config['client_credentials'].blank?
          update_remote_server_config(connection, 'client_credentials', client_credentials)
        end

        exchange_code_for_tokens_for_connection(connection, code)
      end

      # Refresh an expired access token using the refresh token
      # @param connection [UserMcpConnection] The connection with expired token
      # @return [String] New access token
      def refresh_token(connection)
        refresh_token_value = connection.refresh_token
        raise ArgumentError, "No refresh token available" if refresh_token_value.blank?

        # Get OAuth metadata from connection or legacy remote_mcp_server
        oauth_metadata = connection.remote_server_config['oauth_metadata']
        client_credentials = connection.remote_server_config['client_credentials']

        # Fallback to remote_mcp_server for backward compat during migration
        if oauth_metadata.blank? && connection.remote_mcp_server.present?
          oauth_metadata = connection.remote_mcp_server.metadata&.dig('oauth_metadata')
          client_credentials = connection.remote_mcp_server.metadata&.dig('client_credentials')
        end

        raise ArgumentError, "OAuth metadata missing" unless oauth_metadata
        raise ArgumentError, "Client credentials missing" unless client_credentials

        server_name = connection.server_name || connection.remote_mcp_server&.name
        Rails.logger.info("[MCP] Refreshing token for #{server_name}...")

        # Prepare refresh token request
        token_params = {
          grant_type: 'refresh_token',
          client_id: client_credentials['client_id'],
          refresh_token: refresh_token_value
        }

        # Make token request
        response = post_form(oauth_metadata['token_url'], token_params)

        if response['error']
          Rails.logger.error("[MCP] Token refresh failed: #{response['error']} - #{response['error_description']}")
          # Mark connection as needing re-auth
          connection.update!(status: 'expired')
          raise StandardError, "Token refresh failed: #{response['error']} - #{response['error_description']}"
        end

        access_token = response['access_token']

        # Update connection with new tokens
        connection.update!(
          credentials: { 'access_token' => access_token }.to_json,
          refresh_token: response['refresh_token'] || refresh_token_value, # Some servers return new refresh token
          expires_at: response['expires_in'] ? Time.current + response['expires_in'].to_i.seconds : nil,
          status: 'authorized'
        )

        Rails.logger.info("[MCP] Token refreshed successfully for #{server_name}")
        access_token
      end

      # Fetch tools from remote MCP server and cache them in connection
      def fetch_and_cache_tools_for_connection(connection, access_token)
        server_url = connection.server_url
        return unless server_url.present?

        server_name = connection.server_name
        Rails.logger.info("[MCP] Fetching tools from #{server_name}...")

        # Always use HTTP transport (Streamable HTTP)
        tools = fetch_tools_via_streamable_http(server_url, access_token)

        if tools.present?
          formatted_tools = tools.map do |t|
            {
              'name' => t['name'],
              'description' => t['description'] || '',
              'input_schema' => t['inputSchema']
            }
          end

          # Update tools cache in connection
          connection.tools_cache = formatted_tools
          connection.save!

          # Also update the McpServer record
          mcp_server = McpServer.find_by(name: server_name)
          if mcp_server
            mcp_server.update!(tools_cache: formatted_tools, healthy: true)
          end

          Rails.logger.info("[MCP] Cached #{tools.size} tools for #{server_name}")
        end
      rescue StandardError => e
        Rails.logger.warn("[MCP] Failed to fetch tools from #{connection.server_name}: #{e.message}")
      end

      # Legacy method for backward compatibility
      def fetch_and_cache_tools(remote_server, access_token)
        return unless remote_server&.url.present?

        Rails.logger.info("[MCP] Fetching tools from #{remote_server.name}...")

        # Always use HTTP transport (Streamable HTTP)
        tools = fetch_tools_via_streamable_http(remote_server.url, access_token)

        if tools.present?
          # Update the McpServer record with the tools
          mcp_server = McpServer.find_by(name: remote_server.name)
          if mcp_server
            formatted_tools = tools.map do |t|
              {
                'name' => t['name'],
                'description' => t['description'] || '',
                'input_schema' => t['inputSchema']
              }
            end
            mcp_server.update!(tools_cache: formatted_tools, healthy: true)
            Rails.logger.info("[MCP] Cached #{tools.size} tools for #{remote_server.name}")
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[MCP] Failed to fetch tools from #{remote_server.name}: #{e.message}")
      end

      # Fetch tools via Streamable HTTP transport (simple POST)
      def fetch_tools_via_streamable_http(url, access_token)
        # Normalize URL - remove /sse suffix if present, ensure /mcp
        uri = URI(url)
        base_path = uri.path.sub(%r{/sse$}, '')
        base_path = '/mcp' if base_path.empty? || base_path == '/'
        uri.path = base_path

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 15

        # First, try initialize (some servers require this)
        init_request = Net::HTTP::Post.new(uri)
        init_request['Content-Type'] = 'application/json'
        init_request['Accept'] = 'application/json'
        init_request['Authorization'] = "Bearer #{access_token}"
        init_request.body = {
          jsonrpc: '2.0',
          id: SecureRandom.uuid,
          method: 'initialize',
          params: {
            protocolVersion: '2024-11-05',
            capabilities: {},
            clientInfo: { name: 'life-assistant', version: '1.0' }
          }
        }.to_json

        init_response = http.request(init_request)
        Rails.logger.info("[MCP] Streamable HTTP initialize: #{init_response.code}")

        # Now request tools/list
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json, text/event-stream'
        request['Authorization'] = "Bearer #{access_token}"
        request.body = {
          jsonrpc: '2.0',
          id: SecureRandom.uuid,
          method: 'tools/list',
          params: {}
        }.to_json

        response = http.request(request)

        return nil unless response.is_a?(Net::HTTPSuccess)

        data = Mcp::ResponseParser.parse(response.body.to_s, context: "[MCP RemoteOauth]")
        data&.dig('result', 'tools')
      rescue StandardError => e
        Rails.logger.warn("[MCP] Streamable HTTP tools/list failed: #{e.message}")
        nil
      end

      private

      def find_or_create_connection(user, server_info)
        # Check for existing connection by server name
        existing = user.user_mcp_connections.remote_connections.find do |c|
          c.server_name == server_info[:name]
        end
        return existing if existing

        # Create new connection with remote_server_config
        user.user_mcp_connections.create!(
          status: 'pending',
          metadata: {
            'remote_server_config' => {
              'name' => server_info[:name],
              'display_name' => server_info[:display_name],
              'url' => server_info[:url],
              'auth_type' => server_info[:auth_type],
              'description' => server_info[:description],
              'source' => server_info[:source] || 'default'
            }
          }
        )
      end

      def update_remote_server_config(connection, key, value)
        config = connection.remote_server_config.dup
        config[key] = value
        connection.remote_server_config = config
        connection.save!
      end

      def fetch_json(url)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri)
        request['Accept'] = 'application/json'

        response = http.request(request)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue StandardError => e
        Rails.logger.warn("[MCP] Failed to fetch #{url}: #{e.message}")
        nil
      end

      def post_json(url, data)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
        request.body = data.to_json

        response = http.request(request)
        JSON.parse(response.body)
      rescue JSON::ParserError
        { 'error' => 'invalid_response' }
      rescue StandardError => e
        { 'error' => 'request_failed', 'error_description' => e.message }
      end

      def post_form(url, params)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request['Accept'] = 'application/json'
        request.body = URI.encode_www_form(params)

        response = http.request(request)
        JSON.parse(response.body)
      rescue JSON::ParserError
        { 'error' => 'invalid_response' }
      rescue StandardError => e
        { 'error' => 'request_failed', 'error_description' => e.message }
      end
    end
  end
end
