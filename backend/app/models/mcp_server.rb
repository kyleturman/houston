# frozen_string_literal: true

class McpServer < ApplicationRecord
  include Slugifiable

  has_many :user_mcp_connections, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  enum :transport, { http: 'http', stdio: 'stdio' }

  # All valid server names (for validating goal associations)
  # Names are already slugified (lowercase) via Slugifiable concern
  def self.valid_names
    pluck(:name)
  end

  attribute :metadata, :json, default: {}

  # tools_cache is an array of tool hashes {"name","description","params_hint"}

  # Load auth provider config from JSON file
  def auth_provider_config
    return @auth_provider_config if defined?(@auth_provider_config)
    return nil unless metadata&.dig('auth_provider')

    config_path = metadata['auth_provider']
    full_path = find_config_path(config_path)

    return nil unless full_path && File.exist?(full_path)

    @auth_provider_config = JSON.parse(File.read(full_path))
  rescue => e
    Rails.logger.error("Failed to load auth provider config for #{name}: #{e.message}")
    nil
  end

  # Check if server requires authentication
  def requires_auth?
    auth_provider_config&.dig('type') != 'none'
  end

  # Get connection strategy (single or multiple)
  def connection_strategy
    metadata&.dig('connectionStrategy') || 'single'
  end

  # Check if multiple connections are supported
  def supports_multiple_connections?
    connection_strategy == 'multiple'
  end

  # Server type (local or remote)
  def kind
    metadata&.dig('kind') || 'local'
  end

  def local?
    kind == 'local'
  end

  def remote?
    kind == 'remote'
  end

  # Display name (from metadata or formatted name)
  def display_name
    metadata&.dig('display_name') || name.titleize
  end

  # Description
  def description
    metadata&.dig('description')
  end

  # Whether the server is enabled (same as configured - if credentials are set, it's enabled)
  def enabled?
    configured?
  end

  # Get the required credentials for this server from auth provider
  def required_credentials
    auth_provider_config&.dig('backend', 'credentialsEnv') || []
  end

  # Check which required credentials are missing
  def missing_credentials
    required_credentials.select { |env_var| ENV[env_var].blank? }
  end

  # Check if all required credentials are configured
  def configured?
    return true unless requires_auth?
    return true if auth_provider_config&.dig('type') == 'none'

    # For OAuth2 servers, check if client credentials are set
    credentials = required_credentials
    return true if credentials.empty?

    missing_credentials.empty?
  end

  # Get full configuration status with details
  def configuration_status
    auth_config = auth_provider_config
    return { configured: true } unless auth_config

    auth_type = auth_config['type']

    # No auth required
    if auth_type == 'none'
      return { configured: true }
    end

    credentials = required_credentials
    missing = missing_credentials

    if missing.empty?
      {
        configured: true,
        auth_type: auth_type,
        message: 'Server is configured and ready to use'
      }
    else
      {
        configured: false,
        auth_type: auth_type,
        missing: missing,
        message: "Missing credentials: #{missing.join(', ')}"
      }
    end
  end

  private

  def find_config_path(config_path)
    # Try multiple possible locations
    paths = [
      Rails.root.join('mcp', config_path),
      Rails.root.join('..', 'mcp', config_path),
      "/app/mcp/#{config_path}"
    ]
    paths.find { |p| File.exist?(p) }
  end
end