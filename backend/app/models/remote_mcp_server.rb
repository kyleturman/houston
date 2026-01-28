# frozen_string_literal: true

# DEPRECATED: This model is being phased out in favor of storing server config
# directly in UserMcpConnection.metadata['remote_server_config'].
#
# Default servers are now loaded from mcp/default_remote_servers.json at runtime
# via Mcp::DefaultServersService. User connections store all server config in
# UserMcpConnection to ensure proper user scoping (security fix).
#
# This model remains for backward compatibility during migration. After the
# migration (20260115110201_migrate_remote_mcp_server_to_connection_metadata.rb)
# has run on all environments, this model and table can be safely removed.
#
# See: UserMcpConnection, Mcp::DefaultServersService
class RemoteMcpServer < ApplicationRecord
  include Slugifiable

  has_many :user_mcp_connections, dependent: :nullify
  has_many :users, through: :user_mcp_connections

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true, unless: -> { auth_type == 'direct' }
  validates :auth_type, presence: true

  enum :auth_type, {
    oauth2: 'oauth2',
    api_key: 'api_key',
    oauth_consent: 'oauth_consent',
    direct: 'direct'  # No OAuth needed - URL stored in UserMcpConnection.credentials
  }

  # Check if this server requires an OAuth flow
  def requires_oauth?
    %w[oauth2 oauth_consent].include?(auth_type)
  end

  # Check if this is a direct URL server (no OAuth, credentials in URL)
  def direct?
    auth_type == 'direct'
  end

  # Alias base_url to url for consistency with JSON config
  alias_attribute :base_url, :url

  def oauth_config
    config = metadata&.dig('oauth') || {}
    # Interpolate environment variables in OAuth config
    interpolate_env_vars(config)
  end

  def supports_pkce?
    oauth_config['pkce_enabled'] != false
  end

  # Display name for UI (from metadata or titleized name)
  def display_name
    metadata&.dig('display_name') || name.titleize
  end

  private

  def interpolate_env_vars(config)
    return config unless config.is_a?(Hash)

    config.transform_values do |value|
      case value
      when String
        value.gsub(/\$\{(\w+)\}/) { ENV.fetch(::Regexp.last_match(1), '') }
      when Hash
        interpolate_env_vars(value)
      else
        value
      end
    end
  end
end