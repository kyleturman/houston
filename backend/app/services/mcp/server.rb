# frozen_string_literal: true

module Mcp
  class Server
    attr_reader :name, :endpoint, :manifest, :transport, :command, :base_env

    def initialize(name:, endpoint:, manifest: {}, transport: 'http', command: nil, base_env: {})
      @name = name
      @endpoint = endpoint
      @manifest = manifest || {}
      @transport = transport
      @command = command
      @base_env = (base_env || {})
      @client = build_client
    end

    def healthy?
      # Try a 'health' method if available, otherwise a discovery call
      begin
        @client.call('health')
        true
      rescue
        begin
          list_tools
          true
        rescue
          false
        end
      end
    end

    def list_tools
      # Ask the server for tools per MCP spec
      @client.call('tools/list')
    end

    # Invoke a tool by name on this server.
    # args: Hash of parameters
    # user: User instance, used to look up OAuth tokens
    def invoke_tool(name, args:, user:)
      client = build_client(user: user)
      client.call('tools/call', { name: name, arguments: args })
    end

    private

    def build_client(user: nil)
      case @transport.to_s
      when 'stdio'
        cmd = Array(@command)
        env_vars = env_for(user)

        # If command uses Docker, inject env vars as -e flags
        if cmd.first == 'docker'
          # Find the 'run' subcommand and inject -e flags after it
          run_index = cmd.index('run')
          if run_index
            # Insert -e flags after 'run' but before other args
            env_flags = env_vars.flat_map { |k, v| ['-e', "#{k}=#{v}"] }
            cmd = cmd[0..run_index] + env_flags + cmd[(run_index + 1)..-1]
          end
          # Don't pass env to popen since Docker needs explicit -e flags
          Mcp::StdioClient.new(command: cmd, env: {})
        else
          # For non-Docker commands, pass env normally
          Mcp::StdioClient.new(command: cmd, env: env_vars)
        end
      else
        Mcp::JsonRpc.new(endpoint: @endpoint, headers: auth_headers_for(user))
      end
    end

    def env_for(user, connection_id: nil)
      base = @base_env.dup

      return base unless user

      # Get server record to access auth config (names are slugified)
      server_record = McpServer.find_by(name: @name.to_s.downcase)
      return base unless server_record

      # Inject system credentials (PLAID_CLIENT_ID, PLAID_SECRET, etc.)
      if server_record.auth_provider_config
        credentials_env = server_record.auth_provider_config.dig('backend', 'credentialsEnv') || []
        credentials_env.each do |env_var|
          base[env_var] = ENV[env_var] if ENV[env_var]
        end
      end

      # Inject user-specific credentials from connection(s)
      connections = user.user_mcp_connections
        .where(mcp_server: server_record)
        .active_connections
        .order(created_at: :desc)

      connection = if connection_id
                     user.user_mcp_connections.find_by(id: connection_id)
                   else
                     # Default: use first active connection
                     connections.first
                   end

      base.merge!(connection.env_vars) if connection

      # For Plaid: pass ALL connections as JSON for multi-institution support
      if @name == 'plaid' && connections.count > 1
        plaid_connections = connections.map do |conn|
          creds = conn.parsed_credentials
          {
            'access_token' => creds['access_token'] || creds['accessToken'],
            'item_id' => creds['item_id'] || creds['itemId'],
            'institution_name' => conn.institution_name,
            'institution_id' => conn.institution_id,
            'accounts' => conn.accounts
          }
        end.compact
        base['PLAID_CONNECTIONS'] = plaid_connections.to_json
      end

      # For Google servers (Gmail, Calendar): pass ALL connections as JSON for multi-account support
      if ['gmail', 'google-calendar'].include?(@name) && connections.count >= 1
        google_connections = connections.map do |conn|
          creds = conn.parsed_credentials
          {
            'email' => conn.metadata&.dig('email') || 'unknown',
            'access_token' => creds['access_token'],
            'refresh_token' => creds['refresh_token'],
            'expires_at' => creds['expires_at']
          }
        end.compact
        base['GOOGLE_CONNECTIONS'] = google_connections.to_json
        # Remove legacy single-token vars when using multi-connection
        base.delete('GOOGLE_API_ACCESS_TOKEN')
        base.delete('GOOGLE_REFRESH_TOKEN')
      end

      # Write OAuth tokens to filesystem if server requires it
      if connection && server_record.metadata&.dig('token_path').present?
        write_oauth_tokens(connection, server_record)
      end

      # Add user ID for MCP servers that need it
      base['USER_ID'] = user.id.to_s

      base
    end

    # Write user's OAuth tokens to filesystem for MCP packages that require it
    # Configured via tokenPath and tokenFormat in servers.json
    #
    # tokenFormat can be:
    # - A hash with template variables: {"access_token": "{{access_token}}", "expiry_date": "{{expires_at_ms}}"}
    # - Omitted to write credentials as-is
    #
    # Available template variables:
    # - {{access_token}}, {{refresh_token}}, {{scope}}, {{token_type}}
    # - {{expires_at}} - ISO8601 timestamp
    # - {{expires_at_ms}} - Unix timestamp in milliseconds
    # - {{expires_at_s}} - Unix timestamp in seconds
    def write_oauth_tokens(connection, server_record)
      creds = connection.parsed_credentials
      return unless creds['refresh_token'].present?

      # Get token path from server config
      token_path = server_record.metadata&.dig('token_path')
      return unless token_path.present?

      # Expand ~ to home directory
      tokens_path = File.expand_path(token_path)
      tokens_dir = File.dirname(tokens_path)

      FileUtils.mkdir_p(tokens_dir)

      # Get token format template
      token_format = server_record.metadata&.dig('token_format')

      tokens = if token_format.is_a?(Hash)
                 # Build tokens from template
                 build_tokens_from_template(creds, token_format)
               else
                 # Default: write credentials as-is
                 creds
               end

      File.write(tokens_path, tokens.to_json)
      Rails.logger.info("[MCP] Wrote OAuth tokens to #{tokens_path}")
    rescue => e
      Rails.logger.error("[MCP] Failed to write OAuth tokens: #{e.message}")
    end

    # Build tokens hash from template with variable substitution
    def build_tokens_from_template(creds, template)
      # Pre-compute time values
      expires_at_time = creds['expires_at'].present? ? Time.parse(creds['expires_at']) : (Time.now + 3600)

      # Available variables for substitution
      variables = {
        '{{access_token}}' => creds['access_token'],
        '{{refresh_token}}' => creds['refresh_token'],
        '{{scope}}' => creds['scope'] || '',
        '{{token_type}}' => creds['token_type'] || 'Bearer',
        '{{expires_at}}' => expires_at_time.iso8601,
        '{{expires_at_ms}}' => (expires_at_time.to_i * 1000),
        '{{expires_at_s}}' => expires_at_time.to_i
      }

      template.transform_values do |value|
        if value.is_a?(String) && value.start_with?('{{') && value.end_with?('}}')
          variables[value]
        else
          value
        end
      end
    end

    def auth_headers_for(user)
      return {} unless user

      name_slug = @name.to_s.downcase

      # Get server record to find connection (names are slugified)
      server_record = McpServer.find_by(name: name_slug)

      # Try to find connection via local mcp_server first
      connection = nil
      if server_record
        connection = user.user_mcp_connections
          .where(mcp_server: server_record)
          .active_connections
          .first
      end

      # If no local connection, try remote connection (by server_name in metadata)
      unless connection
        connection = user.user_mcp_connections.remote_connections.active_connections.find do |c|
          c.server_name == name_slug
        end
      end

      # If still no connection, check legacy remote_mcp_server path
      unless connection
        if defined?(RemoteMcpServer)
          remote_server = RemoteMcpServer.find_by(name: name_slug)
          if remote_server
            connection = user.user_mcp_connections
              .where(remote_mcp_server: remote_server)
              .active_connections
              .first
          end
        end
      end

      # If no connection found, check if this is a 'direct' auth server (no auth header needed)
      unless connection
        # Check if default server is direct auth type
        default_server = DefaultServersService.instance.find_by_name(name_slug)
        return {} if default_server && default_server.auth_type == 'direct'
      end

      return {} unless connection

      # Direct auth servers don't need auth headers - credentials are in the URL itself
      return {} if connection.direct_auth?

      creds = connection.parsed_credentials
      access_token = creds['access_token']

      return {} unless access_token.present?

      # Check if token is expired and refresh if needed
      # For remote MCP servers, expires_at is stored on the connection directly
      # For local servers, it's in the credentials JSON
      expires_at = connection.expires_at || (creds['expires_at'].present? ? Time.parse(creds['expires_at']) : nil) rescue nil

      if expires_at && expires_at < Time.current
        Rails.logger.info("[MCP] Access token expired (expires_at: #{expires_at}), refreshing...")
        access_token = refresh_access_token(connection, server_record)
      end

      # Return bearer token header for OAuth2 servers
      { 'Authorization' => "Bearer #{access_token}" }
    end

    def refresh_access_token(connection, server_record)
      creds = connection.parsed_credentials
      refresh_token_value = creds['refresh_token'] || connection.refresh_token
      return nil unless refresh_token_value.present?

      # Check if this is a remote server connection (uses OAuth via RemoteOauthService)
      if connection.remote_server? && connection.requires_oauth?
        # Use RemoteOauthService for remote MCP servers
        new_token = Mcp::RemoteOauthService.refresh_token(connection)
        Rails.logger.info("[MCP] Successfully refreshed access token for remote MCP server")
        return new_token
      end

      # Use auth provider to refresh token (for local servers)
      auth_service = Mcp::AuthService.new(server_record)
      refreshed_connection = auth_service.refresh(connection: connection)

      Rails.logger.info("[MCP] Successfully refreshed access token")
      refreshed_connection.parsed_credentials['access_token']
    rescue => e
      Rails.logger.error("[MCP] Token refresh error: #{e.message}")
      creds['access_token']
    end
  end
end
