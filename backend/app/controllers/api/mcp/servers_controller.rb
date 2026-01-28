# frozen_string_literal: true

class Api::Mcp::ServersController < Api::BaseController
  # GET /api/mcp/servers - List all MCP servers with user connection status
  # Returns servers grouped by: local (configured), local_unconfigured, remote
  def index
    # Ensure MCP config is loaded (but don't reload on every request - that's slow)
    Mcp::ConnectionManager.instance.load!

    # Get all servers from McpServer (populated by ConnectionManager)
    all_mcp_servers = McpServer.all

    # Separate local servers into configured and unconfigured
    local_servers = []
    unconfigured_servers = []

    all_mcp_servers.each do |mcp_server|
      next if mcp_server.remote?

      server_data = build_local_server_response(mcp_server)

      if mcp_server.enabled? && mcp_server.configured?
        local_servers << server_data
      else
        unconfigured_servers << server_data
      end
    end

    # Build remote servers list:
    # 1. Start with default servers from JSON config
    # 2. Overlay user's connection status
    # 3. Add user-added servers (only visible to this user)
    remote_servers = build_remote_servers_list

    render json: {
      servers: local_servers + remote_servers,
      local_servers: local_servers,
      unconfigured_servers: unconfigured_servers,
      remote_servers: remote_servers,
      local_count: local_servers.size,
      unconfigured_count: unconfigured_servers.size,
      remote_count: remote_servers.size
    }
  end

  # GET /api/mcp/servers/:id - Get details for a specific remote MCP server
  def show
    server_info = find_server_info(params[:id])
    raise ActiveRecord::RecordNotFound, "Server not found: #{params[:id]}" unless server_info

    connection = server_info[:connection]

    render json: {
      server: {
        id: server_info[:id],
        name: server_info[:name],
        display_name: server_info[:display_name],
        base_url: server_info[:url],
        auth_type: server_info[:auth_type],
        description: server_info[:description],
        source: server_info[:source]
      },
      connection: connection ? {
        status: connection.status,
        expires_at: connection.expires_at,
        needs_refresh: connection.needs_refresh?,
        valid_token: connection.valid_token?,
        metadata: connection.metadata
      } : nil
    }
  end

  # POST /api/mcp/servers/:id/connect - Initiate connection to remote MCP server
  def connect
    server_info = find_server_info(params[:id])
    raise ArgumentError, "Server not found: #{params[:id]}" unless server_info

    auth_type = server_info[:auth_type]

    case auth_type
    when 'oauth2'
      handle_oauth2_connect(server_info)
    when 'oauth_consent'
      handle_oauth_consent_connect(server_info)
    when 'api_key'
      handle_api_key_connect(server_info)
    when 'direct'
      handle_direct_connect(server_info)
    else
      render json: { error: 'Unsupported auth type' }, status: :unprocessable_entity
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/mcp/servers/:id/disconnect - Disconnect from remote MCP server
  def disconnect
    server_info = find_server_info(params[:id])
    raise ArgumentError, "Server not found: #{params[:id]}" unless server_info

    connection = server_info[:connection]

    if connection
      connection.update!(
        status: 'disconnected',
        credentials: nil,
        refresh_token: nil,
        expires_at: nil
      )
    end

    render json: { ok: true, status: 'disconnected' }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Build list of remote servers combining defaults and user connections
  # Supports multi-account: each server can have multiple connections (workspaces/accounts)
  def build_remote_servers_list
    # Get user's remote connections grouped by server name
    connections_by_server = current_user.user_mcp_connections
      .remote_connections
      .group_by(&:server_name)

    servers = []

    # 1. Add all default servers from JSON config
    Mcp::DefaultServersService.instance.list_all.each do |default_server|
      connections = connections_by_server[default_server.name] || []

      servers << build_remote_server_hash(
        id: "default_#{default_server.name}",
        name: default_server.name,
        display_name: default_server.display_name,
        url: default_server.url,
        auth_type: default_server.auth_type,
        description: default_server.description,
        source: 'default',
        connections: connections
      )
    end

    # 2. Add user-added servers (only this user's)
    # Group by server name to handle multiple connections per user-added server
    user_added_servers = current_user.user_mcp_connections
      .remote_connections
      .select(&:user_added?)
      .group_by(&:server_name)

    user_added_servers.each do |server_name, connections|
      # Use the first connection for server metadata (they should all be the same)
      first_conn = connections.first

      servers << build_remote_server_hash(
        id: "user_#{first_conn.id}",
        name: server_name,
        display_name: first_conn.server_display_name,
        url: first_conn.server_url,
        auth_type: first_conn.server_auth_type,
        description: first_conn.remote_server_config['description'],
        source: 'user_added',
        connections: connections
      )
    end

    servers
  end

  def build_remote_server_hash(id:, name:, display_name:, url:, auth_type:, description:, source:, connections:)
    # Filter to get active connections
    active_connections = connections.select { |c| c.active? || c.authorized? }
    primary_connection = active_connections.first || connections.first

    # Determine overall status
    connection_status = if active_connections.any?
      active_connections.any?(&:expired?) ? 'expired' : 'connected'
    elsif connections.any?
      connections.first.status  # pending, disconnected, revoked
    else
      'available'
    end

    # Build connections array for multi-account display
    connections_data = connections.map do |conn|
      {
        id: conn.id,
        connection_identifier: conn.connection_identifier,
        status: conn.status,
        display_label: conn.display_label,
        workspace_name: conn.workspace_name,
        email: conn.email,
        expires_at: conn.expires_at,
        needs_refresh: conn.needs_refresh?
      }.compact
    end

    {
      id: id,
      name: display_name || name&.titleize,
      internal_name: name,
      type: 'remote',
      base_url: url,
      auth_type: auth_type == 'direct' ? nil : auth_type,
      description: description,
      connection_status: connection_status,
      connection_count: connections.size,
      connections: connections_data.presence,
      expires_at: primary_connection&.expires_at,
      needs_refresh: primary_connection&.needs_refresh? || false,
      tools: Array(primary_connection&.tools_cache).map { |t| t['name'] || t[:name] }.compact,
      is_url_server: auth_type == 'direct' ? true : nil,
      source: source
    }.compact
  end

  def build_local_server_response(mcp_server)
    # Get connection count for this server
    connections_count = UserMcpConnection.where(
      user: current_user,
      mcp_server: mcp_server
    ).active_connections.count

    # Get auth handler type from provider config for iOS
    auth_type = if mcp_server.requires_auth?
      handler = mcp_server.auth_provider_config&.dig('ios', 'handler')
      handler || 'oauth2'
    end

    # Determine connection status
    connection_status = if connections_count > 0
      'connected'
    elsif !mcp_server.configured?
      'needs_setup'
    elsif mcp_server.healthy
      'available'
    else
      'disconnected'
    end

    {
      id: "local_#{mcp_server.name}",
      name: mcp_server.display_name,
      internal_name: mcp_server.name,
      type: 'local',
      endpoint: mcp_server.endpoint,
      healthy: mcp_server.healthy,
      tools: Array(mcp_server.tools_cache).map { |t| t['name'] || t[:name] }.compact,
      connection_strategy: mcp_server.requires_auth? ? mcp_server.connection_strategy : nil,
      auth_type: auth_type,
      connection_status: connection_status,
      description: mcp_server.description,
      configuration_status: mcp_server.configuration_status,
      enabled: mcp_server.enabled?,
      configured: mcp_server.configured?
    }.compact
  end

  # Find server info by ID (handles various ID formats)
  # Returns hash with :id, :name, :url, :auth_type, :connection, :source
  def find_server_info(server_id)
    id_str = server_id.to_s

    # Handle "default_servername" format
    if id_str.start_with?('default_')
      server_key = id_str.sub('default_', '')
      default_server = Mcp::DefaultServersService.instance.find_by_name(server_key)
      return nil unless default_server

      connection = find_user_connection_by_name(server_key)

      return {
        id: id_str,
        name: default_server.name,
        display_name: default_server.display_name,
        url: default_server.url,
        auth_type: default_server.auth_type,
        description: default_server.description,
        source: 'default',
        connection: connection,
        default_config: default_server
      }
    end

    # Handle "user_123" format (UserMcpConnection ID)
    if id_str.start_with?('user_')
      conn_id = id_str.sub('user_', '')
      connection = current_user.user_mcp_connections.find_by(id: conn_id)
      return nil unless connection

      return {
        id: id_str,
        name: connection.server_name,
        display_name: connection.server_display_name,
        url: connection.server_url,
        auth_type: connection.server_auth_type,
        description: connection.remote_server_config['description'],
        source: 'user_added',
        connection: connection
      }
    end

    # Handle "remote_servername" format (legacy, check defaults then user connections)
    if id_str.start_with?('remote_')
      server_key = id_str.sub('remote_', '')

      # Check defaults first
      default_server = Mcp::DefaultServersService.instance.find_by_name(server_key)
      if default_server
        connection = find_user_connection_by_name(server_key)
        return {
          id: "default_#{server_key}",
          name: default_server.name,
          display_name: default_server.display_name,
          url: default_server.url,
          auth_type: default_server.auth_type,
          description: default_server.description,
          source: 'default',
          connection: connection,
          default_config: default_server
        }
      end

      # Check user connections
      connection = find_user_connection_by_name(server_key)
      return nil unless connection

      return {
        id: "user_#{connection.id}",
        name: connection.server_name,
        display_name: connection.server_display_name,
        url: connection.server_url,
        auth_type: connection.server_auth_type,
        description: connection.remote_server_config['description'],
        source: 'user_added',
        connection: connection
      }
    end

    # Handle numeric ID (legacy RemoteMcpServer ID - check if it has a connection)
    if id_str.match?(/^\d+$/)
      # Try to find by legacy remote_mcp_server_id
      connection = current_user.user_mcp_connections.find_by(remote_mcp_server_id: id_str)
      if connection
        return {
          id: "user_#{connection.id}",
          name: connection.server_name,
          display_name: connection.server_display_name,
          url: connection.server_url,
          auth_type: connection.server_auth_type,
          description: connection.remote_server_config['description'],
          source: connection.user_added? ? 'user_added' : 'default',
          connection: connection
        }
      end

      # Also check RemoteMcpServer for backward compat during migration
      if defined?(RemoteMcpServer)
        remote_server = RemoteMcpServer.find_by(id: id_str)
        if remote_server
          connection = current_user.user_mcp_connections.find_by(remote_mcp_server: remote_server)
          return {
            id: id_str,
            name: remote_server.name,
            display_name: remote_server.display_name,
            url: remote_server.url,
            auth_type: remote_server.auth_type,
            description: remote_server.description,
            source: remote_server.metadata&.dig('user_added') ? 'user_added' : 'default',
            connection: connection
          }
        end
      end
    end

    nil
  end

  def find_user_connection_by_name(server_name)
    # First try to find by remote_server_config name
    current_user.user_mcp_connections.remote_connections.find do |conn|
      conn.server_name == server_name
    end
  end

  # Create or find connection for a server and store remote_server_config
  def find_or_create_connection(server_info)
    # Try to find existing connection
    connection = server_info[:connection]

    if connection.nil?
      # Create new connection with remote_server_config in metadata
      connection = current_user.user_mcp_connections.new(
        status: 'pending',
        metadata: {
          'remote_server_config' => {
            'name' => server_info[:name],
            'display_name' => server_info[:display_name],
            'url' => server_info[:url],
            'auth_type' => server_info[:auth_type],
            'description' => server_info[:description],
            'source' => server_info[:source]
          }
        }
      )
    end

    connection
  end

  def handle_oauth2_connect(server_info)
    oauth_callback_uri = request.base_url + '/api/mcp/oauth/callback'
    client_redirect_uri = params[:redirect_uri]

    # Create pending connection first
    connection = find_or_create_connection(server_info)
    connection.status = 'pending'
    connection.save!

    authorize_url = Mcp::OauthService.build_authorize_url(
      server_info,
      oauth_callback_uri,
      current_user,
      client_redirect_uri: client_redirect_uri
    )

    render json: {
      type: 'oauth2',
      authorize_url: authorize_url,
      server_name: server_info[:name],
      server_id: server_info[:id]
    }
  end

  def handle_oauth_consent_connect(server_info)
    oauth_callback_uri = request.base_url + '/api/mcp/oauth/callback'
    client_redirect_uri = params[:redirect_uri]

    # Create pending connection first
    connection = find_or_create_connection(server_info)
    connection.status = 'pending'
    connection.save!

    authorize_url = Mcp::RemoteOauthService.build_authorize_url_for_remote_mcp(
      server_info,
      oauth_callback_uri,
      current_user,
      client_redirect_uri: client_redirect_uri
    )

    render json: {
      type: 'oauth_consent',
      authorize_url: authorize_url,
      server_name: server_info[:name],
      server_id: server_info[:id]
    }
  end

  def handle_api_key_connect(server_info)
    api_key = params[:api_key]
    raise ArgumentError, 'API key required' if api_key.blank?

    connection = find_or_create_connection(server_info)
    connection.update!(
      credentials: { 'api_key' => api_key }.to_json,
      status: 'active'
    )

    render json: {
      type: 'api_key',
      status: 'connected',
      server_name: server_info[:name],
      server_id: server_info[:id]
    }
  end

  def handle_direct_connect(server_info)
    url = params[:url] || server_info[:url]
    raise ArgumentError, 'URL required for direct connection' if url.blank?

    connection = find_or_create_connection(server_info)
    connection.update!(
      credentials: { 'url' => url }.to_json,
      status: 'active'
    )

    render json: {
      type: 'direct',
      status: 'connected',
      server_name: server_info[:name],
      server_id: server_info[:id]
    }
  end
end
