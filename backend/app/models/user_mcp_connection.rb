class UserMcpConnection < ApplicationRecord
  belongs_to :user
  belongs_to :mcp_server, optional: true
  belongs_to :remote_mcp_server, optional: true  # DEPRECATED - will be removed

  # Support both new (active/disconnected) and legacy (pending/authorized/expired/revoked) statuses
  enum :status, {
    active: 'active',
    disconnected: 'disconnected',
    pending: 'pending',
    authorized: 'authorized',
    expired: 'expired',
    revoked: 'revoked'
  }, default: :active

  # Callbacks for remote server support
  before_validation :sync_remote_server_name
  before_validation :ensure_connection_identifier

  # === Uniqueness Validations ===
  # Local servers: unique by (user, mcp_server, connection_identifier)
  validates :user_id, uniqueness: { scope: [:mcp_server_id, :connection_identifier] }, if: -> { mcp_server_id.present? }

  # Remote servers: unique by (user, remote_server_name, connection_identifier) - enforced at DB level
  # The DB index idx_user_remote_server_connection handles this for new connections
  # Legacy remote_mcp_server_id connections still use old constraint
  validates :user_id, uniqueness: { scope: :remote_mcp_server_id }, if: -> { remote_mcp_server_id.present? }

  validates :status, presence: true
  validate :valid_server_reference

  # === Server config accessors for remote servers ===
  # Remote servers store their config in metadata['remote_server_config']
  # This is only used for remote connections (where mcp_server_id is nil)

  def remote_server_config
    metadata&.dig('remote_server_config') || {}
  end

  def remote_server_config=(config)
    self.metadata = (metadata || {}).merge('remote_server_config' => config)
  end

  # Server name (slug identifier) - works for both local and remote
  def server_name
    return mcp_server.name if mcp_server_id.present?
    return remote_mcp_server&.name if remote_mcp_server_id.present?  # DEPRECATED path
    remote_server_config['name']
  end

  # Display name for UI
  def server_display_name
    return mcp_server.display_name if mcp_server_id.present?
    return remote_mcp_server&.display_name if remote_mcp_server_id.present?  # DEPRECATED path
    remote_server_config['display_name'] || remote_server_config['name']&.titleize
  end

  # Server URL - for remote servers
  def server_url
    # First check credentials (for direct auth servers)
    url_from_creds = parsed_credentials['url']
    return url_from_creds if url_from_creds.present?

    # Fall back to remote_server_config
    return remote_server_config['url'] if remote_server_config['url'].present?

    # DEPRECATED: fall back to remote_mcp_server
    remote_mcp_server&.url
  end

  # Auth type for this connection's server
  def server_auth_type
    return remote_server_config['auth_type'] if remote_server_config['auth_type'].present?
    return remote_mcp_server&.auth_type if remote_mcp_server_id.present?  # DEPRECATED path
    nil
  end

  # Check if this is a user-added server (vs default from JSON)
  def user_added?
    remote_server_config['source'] == 'user_added'
  end

  # Check if this was a default server (from JSON config)
  def default_server?
    remote_server_config['source'] == 'default'
  end

  # Check if this is a remote server connection (vs local MCP server)
  def remote_server?
    mcp_server_id.blank?
  end

  # Check if this server requires OAuth
  def requires_oauth?
    %w[oauth2 oauth_consent].include?(server_auth_type)
  end

  # Check if this is a direct auth server (URL-only, no OAuth)
  def direct_auth?
    server_auth_type == 'direct'
  end

  private

  # Sync remote_server_name column from metadata for DB-level uniqueness
  def sync_remote_server_name
    return unless remote_server?

    # Populate from remote_server_config (new model)
    if remote_server_config['name'].present?
      self.remote_server_name = remote_server_config['name']
    # Fallback: populate from legacy remote_mcp_server (deprecated)
    elsif remote_mcp_server_id.present? && remote_mcp_server&.name.present?
      self.remote_server_name = remote_mcp_server.name
    end
  end

  # Ensure connection_identifier is set for multi-account support
  def ensure_connection_identifier
    return if connection_identifier.present?

    # For remote servers, generate a default identifier
    # This can be overridden with workspace_id/account_id from OAuth response
    if remote_server?
      self.connection_identifier = SecureRandom.uuid
    end
  end

  def valid_server_reference
    has_local = mcp_server_id.present?
    has_remote_legacy = remote_mcp_server_id.present?
    has_remote_config = remote_server_config['name'].present?

    if has_local && (has_remote_legacy || has_remote_config)
      errors.add(:base, "Connection cannot reference both local and remote server")
    elsif !has_local && !has_remote_legacy && !has_remote_config
      errors.add(:base, "Connection must have server reference or remote_server_config")
    end
  end

  public

  attribute :metadata, :json, default: {}

  # Encrypt credentials and refresh token
  encrypts :credentials, deterministic: false
  encrypts :refresh_token, deterministic: false

  # Scopes
  scope :active_connections, -> { where(status: ['active', 'authorized']) }
  scope :remote_connections, -> { where(mcp_server_id: nil) }
  scope :for_server, ->(server_name) {
    joins(:mcp_server).where(mcp_servers: { name: server_name })
  }
  scope :for_remote_server, ->(server_name) {
    where(mcp_server_id: nil, remote_server_name: server_name)
  }

  # Get active connection for a user and server
  def self.active_connection_for(user, server_name)
    for_server(server_name).where(user: user).active_connections.order(created_at: :desc).first
  end

  # Get all active connections for a user and remote server (supports multi-account)
  def self.active_remote_connections_for(user, server_name)
    for_remote_server(server_name).where(user: user).active_connections.order(created_at: :desc)
  end

  # Get environment variables for this connection (for MCP stdio servers)
  def env_vars
    return {} unless mcp_server&.auth_provider_config

    mapping = mcp_server.auth_provider_config.dig('runtime', 'envMapping') || {}
    creds = parsed_credentials

    # mapping format: { "credentialKey": "ENV_VAR_NAME" }
    # Transform to { "ENV_VAR_NAME": credential_value }
    # Note: mapping uses camelCase keys but credentials use snake_case
    mapping.each_with_object({}) do |(cred_key, env_var_name), result|
      # Try camelCase key, snake_case conversion, and symbol versions
      snake_key = cred_key.to_s.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
      value = creds[cred_key] || creds[cred_key.to_sym] || creds[snake_key] || creds[snake_key.to_sym]
      result[env_var_name] = value if value.present?
    end
  end

  # Get display label for UI
  def display_label
    if institution_name.present?
      # Plaid: show institution and account count
      account_count = metadata&.dig('accounts')&.size || 0
      "#{institution_name} - #{account_count} account(s)"
    elsif email.present?
      # Google OAuth: show connected email
      email
    elsif workspace_name.present?
      # Remote OAuth with workspace (Notion, Linear, etc.)
      workspace_name
    elsif mcp_server
      "#{mcp_server.display_name || mcp_server.name} connection"
    elsif server_display_name.present?
      "#{server_display_name} connection"
    else
      "Connection #{id}"
    end
  end

  # Workspace name for multi-account remote servers (e.g., Notion workspace)
  def workspace_name
    metadata&.dig('workspace_name') || metadata&.dig('token_response_info', 'workspace_name')
  end

  # Workspace ID for identifying unique accounts
  def workspace_id
    metadata&.dig('workspace_id') || metadata&.dig('token_response_info', 'workspace_id')
  end

  # Set a meaningful connection identifier from OAuth response
  # Call this after OAuth token exchange when workspace/account info is available
  def set_connection_identifier_from_oauth(token_response_info)
    return unless token_response_info.is_a?(Hash)

    # Try common identifier fields from various OAuth providers
    identifier = token_response_info['workspace_id'] ||  # Notion, Slack
                 token_response_info['team_id'] ||        # Slack
                 token_response_info['bot_id'] ||         # Various
                 token_response_info['owner']&.dig('user', 'id') ||  # Notion
                 token_response_info['account_id']        # Generic

    if identifier.present?
      self.connection_identifier = identifier.to_s
    end

    # Store workspace name for display
    workspace = token_response_info['workspace_name'] ||
                token_response_info['team_name'] ||
                token_response_info['team']&.dig('name')

    if workspace.present?
      self.metadata = (metadata || {}).merge('workspace_name' => workspace)
    end

    # Store workspace_id if different from connection_identifier
    if token_response_info['workspace_id'].present?
      self.metadata = (metadata || {}).merge('workspace_id' => token_response_info['workspace_id'])
    end
  end

  def email
    metadata&.dig('email')
  end

  # Parse credentials JSON
  def parsed_credentials
    return {} if credentials.blank?
    JSON.parse(credentials)
  rescue JSON::ParserError
    {}
  end

  # Store accessor helpers for common metadata fields
  def institution_name
    metadata&.dig('institution_name')
  end

  def institution_id
    metadata&.dig('institution_id')
  end

  def accounts
    metadata&.dig('accounts') || []
  end

  # Legacy methods for backward compat with remote servers
  def expired?
    expires_at && expires_at < Time.current
  end

  def needs_refresh?
    expired? && refresh_token.present?
  end

  def valid_token?
    (active? || authorized?) && !expired?
  end

  # Tools cache stored in metadata
  def tools_cache
    metadata&.dig('tools_cache') || []
  end

  def tools_cache=(tools)
    self.metadata = (metadata || {}).merge('tools_cache' => tools)
  end

  # Error tracking in metadata
  def error_message
    metadata&.dig('error_message')
  end

  def set_error(message)
    self.metadata = (metadata || {}).merge(
      'error_message' => message,
      'last_error_at' => Time.current.iso8601
    )
  end

  def clear_error
    self.metadata = (metadata || {}).except('error_message', 'last_error_at')
  end

  # Last connected tracking
  def last_connected_at
    val = metadata&.dig('last_connected_at')
    val ? Time.zone.parse(val) : nil
  end

  def touch_last_connected
    self.metadata = (metadata || {}).merge('last_connected_at' => Time.current.iso8601)
  end
end
