# frozen_string_literal: true

class Api::Mcp::OauthController < Api::BaseController
  # Skip auth for callback - it comes from external OAuth redirect
  skip_before_action :authenticate_user!, only: [:callback]

  # GET /api/mcp/oauth/authorize?server_id=123&redirect_uri=...
  # Initiates OAuth 2.1 PKCE flow for remote MCP server
  def authorize
    remote_server = RemoteMcpServer.find(params[:server_id])
    redirect_uri = params[:redirect_uri].presence || request.base_url + '/api/mcp/oauth/callback'
    
    authorize_url = Mcp::OauthService.build_authorize_url(
      remote_server, 
      redirect_uri, 
      current_user
    )
    
    render json: { 
      authorize_url: authorize_url,
      server_name: remote_server.name 
    }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/mcp/oauth/callback?code=...&state=...
  # Handles OAuth callback and exchanges code for tokens
  # Note: Auth is skipped - we find user via state parameter
  def callback
    code = params[:code]
    state = params[:state]

    raise ArgumentError, 'Authorization code required' if code.blank?
    raise ArgumentError, 'State parameter required' if state.blank?

    # First, check for local server OAuth (state stored in cache)
    cached_state = Rails.cache.read("oauth_state:#{state}")
    if cached_state
      handle_local_oauth_callback(code, state, cached_state)
      return
    end

    # Fall back to remote server OAuth (state stored in DB)
    pending_connection = UserMcpConnection.find_by(state: state, status: 'pending')
    raise ArgumentError, 'Invalid state or connection not found' unless pending_connection

    remote_server = pending_connection.remote_mcp_server
    user = pending_connection.user

    # Get the stored client_redirect_uri from connection metadata (set during initiation)
    # This is where we redirect after successful token exchange (e.g., iOS app)
    client_redirect_uri = pending_connection.metadata&.dig('client_redirect_uri')

    # Use the appropriate service based on whether this is a remote MCP server with oauth_consent
    # (which uses discovered OAuth metadata) or a regular oauth2 server (with static config)
    connection = if remote_server.oauth_consent? && remote_server.metadata&.dig('oauth_metadata').present?
      Mcp::RemoteOauthService.exchange_code_for_tokens(
        remote_server,
        code,
        state,
        user
      )
    else
      Mcp::OauthService.exchange_code_for_tokens(
        remote_server,
        code,
        state,
        user
      )
    end

    # Check if we should redirect to a mobile app (custom URL scheme)
    if client_redirect_uri.present?
      # Redirect back to client (e.g., iOS app)
      redirect_to "#{client_redirect_uri}?status=success&server_id=#{remote_server.id}", allow_other_host: true
    else
      # Web flow - render JSON response
      render json: {
        ok: true,
        server_name: remote_server.name,
        server_id: remote_server.id,
        status: connection.status,
        expires_at: connection.expires_at
      }
    end
  rescue => e
    handle_oauth_error(e)
  end

  private

  def handle_local_oauth_callback(code, state, cached_state)
    user = User.find(cached_state[:user_id])
    server_name = cached_state[:server_name]
    redirect_uri = cached_state[:redirect_uri]
    app_redirect_scheme = cached_state[:app_redirect_scheme] || 'heyhouston'

    # Exchange code for tokens using the AuthService
    connection = Mcp::AuthService.exchange(
      server_name: server_name,
      user: user,
      credentials: { code: code, state: state, redirect_uri: redirect_uri },
      metadata: {}
    )

    # Clear the cached state
    Rails.cache.delete("oauth_state:#{state}")

    # Redirect back to app
    app_callback = "#{app_redirect_scheme}://oauth-callback?status=success&server=#{CGI.escape(server_name)}"
    redirect_to app_callback, allow_other_host: true
  rescue => e
    app_scheme = cached_state&.dig(:app_redirect_scheme) || 'heyhouston'
    error_callback = "#{app_scheme}://oauth-callback?status=error&error=#{CGI.escape(e.message)}"
    redirect_to error_callback, allow_other_host: true
  end

  def handle_oauth_error(error)
    # Try to get stored client_redirect_uri for error handling
    state = params[:state]

    # Check cache first
    cached = Rails.cache.read("oauth_state:#{state}")
    if cached
      app_scheme = cached[:app_redirect_scheme] || 'heyhouston'
      redirect_to "#{app_scheme}://oauth-callback?status=error&error=#{CGI.escape(error.message)}", allow_other_host: true
      return
    end

    # Check DB
    pending = UserMcpConnection.find_by(state: state)
    client_uri = pending&.metadata&.dig('client_redirect_uri')

    if client_uri.present?
      redirect_to "#{client_uri}?status=error&error=#{CGI.escape(error.message)}", allow_other_host: true
    else
      render json: { ok: false, error: error.message }, status: :unprocessable_entity
    end
  end

  # POST /api/mcp/oauth/refresh?server_id=123
  # Refreshes access token using refresh token
  def refresh
    remote_server = RemoteMcpServer.find(params[:server_id])
    connection = UserMcpConnection.find_by!(
      user: current_user,
      remote_mcp_server: remote_server
    )

    success = Mcp::OauthService.refresh_token(connection)
    
    if success
      render json: { 
        ok: true,
        status: connection.status,
        expires_at: connection.expires_at
      }
    else
      render json: { 
        ok: false, 
        error: 'Token refresh failed',
        status: connection.status
      }, status: :unprocessable_entity
    end
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/mcp/oauth/revoke?server_id=123
  # Revokes OAuth connection
  def revoke
    remote_server = RemoteMcpServer.find(params[:server_id])
    connection = UserMcpConnection.find_by!(
      user: current_user,
      remote_mcp_server: remote_server
    )

    connection.update!(
      status: 'revoked',
      credentials: nil,
      refresh_token: nil,
      expires_at: nil
    )

    render json: { ok: true }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end
end
