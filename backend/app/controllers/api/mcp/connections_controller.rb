# frozen_string_literal: true

# Generic controller for MCP server connections
# Works for ANY MCP server (plaid, brave-search, etc.)
class Api::Mcp::ConnectionsController < Api::BaseController
  # POST /api/mcp/:server_name/auth/initiate
  # Initiate authentication flow for a server
  def initiate
    result = ::Mcp::AuthService.initiate(
      server_name: params[:server_name],
      user: current_user,
      redirect_uri: params[:redirect_uri]
    )

    render json: { success: true, **result }
  rescue ::Mcp::AuthService::AuthError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  # POST /api/mcp/:server_name/auth/exchange
  # Exchange credentials (public_token, api_key, auth_code) for connection
  def exchange
    connection = ::Mcp::AuthService.exchange(
      server_name: params[:server_name],
      user: current_user,
      credentials: (params[:credentials] || {}).to_unsafe_h,
      metadata: (params[:metadata] || {}).to_unsafe_h
    )

    render json: {
      success: true,
      connection: serialize_connection(connection)
    }
  rescue ::Mcp::AuthService::AuthError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  # GET /api/mcp/:server_name/connections
  # List all connections for a server
  def index
    connections = ::Mcp::AuthService.connections_for(
      server_name: params[:server_name],
      user: current_user
    )

    render json: {
      success: true,
      connections: connections.map { |c| serialize_connection(c) }
    }
  end

  # GET /api/mcp/:server_name/status
  # Get connection status for a server
  def status
    status_info = ::Mcp::AuthService.status(
      server_name: params[:server_name],
      user: current_user
    )

    render json: { success: true, **status_info }
  end

  # DELETE /api/mcp/connections/:id
  # Disconnect a specific connection
  def destroy
    ::Mcp::AuthService.disconnect(
      connection_id: params[:id],
      user: current_user
    )

    render json: { success: true, message: 'Connection disconnected' }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: 'Connection not found' }, status: :not_found
  end

  # POST /api/mcp/url_servers
  # Add a custom MCP server with auto-detection of auth requirements
  # Accepts: { name: "Server Name", url: "https://..." }
  # Returns: { success: true, status: "enabled"|"available", ... }
  def create_from_url
    url = params[:url]&.strip
    server_name = params[:name]&.strip || params[:server_name]&.strip

    if url.blank?
      return render json: { success: false, error: 'URL is required' }, status: :unprocessable_entity
    end

    if server_name.blank?
      return render json: { success: false, error: 'Server name is required' }, status: :unprocessable_entity
    end

    # Validate URL format
    begin
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTPS)
        return render json: { success: false, error: 'URL must be HTTPS' }, status: :unprocessable_entity
      end
    rescue URI::InvalidURIError
      return render json: { success: false, error: 'Invalid URL format' }, status: :unprocessable_entity
    end

    # Use unified add server flow with auto-detection
    result = ::Mcp::UrlServerService.add_server(
      user: current_user,
      name: server_name,
      url: url
    )

    if result[:success]
      if result[:action] == :enabled
        # Server connected directly (no auth needed)
        render json: {
          success: true,
          status: 'enabled',
          connection: result[:connection] ? serialize_url_connection(result[:connection]) : nil,
          tools_count: result[:tools_count],
          display_name: result[:display_name]
        }.compact
      else
        # Server needs auth - return as "available"
        render json: {
          success: true,
          status: 'available',
          server_id: result[:server_id],
          server_name: result[:server_name],
          needs_auth: result[:needs_auth],
          auth_type: result[:auth_type]
        }
      end
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  # DELETE /api/mcp/url_servers/:server_name
  # Disconnect a URL-based server
  def destroy_url_server
    server_name = params[:server_name]

    result = ::Mcp::UrlServerService.disconnect(
      user: current_user,
      server_name: server_name
    )

    if result[:success]
      render json: { success: true, message: 'Server disconnected' }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  # GET /api/mcp/url_servers/:server_name
  # Get status of a URL-based server
  def url_server_status
    server_name = params[:server_name]

    result = ::Mcp::UrlServerService.status(
      user: current_user,
      server_name: server_name
    )

    render json: { success: true, **result }
  end

  private

  def serialize_url_connection(connection)
    {
      id: connection.id,
      serverName: connection.server_name,
      status: connection.status,
      toolsCount: connection.tools_cache&.size || 0,
      createdAt: connection.created_at
    }
  end

  def serialize_connection(connection)
    # Handle both local (mcp_server) and remote (remote_mcp_server) connections
    server_name = if connection.mcp_server
      connection.mcp_server.name
    elsif connection.remote_mcp_server
      connection.remote_mcp_server.name
    else
      'unknown'
    end

    {
      id: connection.id,
      serverName: server_name,
      label: connection.display_label,
      institutionName: connection.institution_name,
      accountCount: connection.accounts.size,
      status: connection.status,
      metadata: connection.metadata,
      expiresAt: connection.expires_at,
      createdAt: connection.created_at
    }.compact
  end
end
