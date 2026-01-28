# frozen_string_literal: true

module Mcp
  # Service for loading and caching default MCP servers from JSON config.
  # Default servers are defined in mcp/default_remote_servers.json and are
  # available to all users (but require connection/auth to use).
  class DefaultServersService
    include Singleton

    # Struct to represent a default server definition
    ServerConfig = Struct.new(
      :name,          # Slugified identifier (e.g., "notion")
      :display_name,  # Human-readable name (e.g., "Notion")
      :description,
      :url,
      :auth_type,     # oauth_consent, oauth2, api_key
      :enabled,
      :metadata,
      keyword_init: true
    ) do
      def requires_oauth?
        %w[oauth2 oauth_consent].include?(auth_type)
      end

      def to_h
        {
          'name' => name,
          'display_name' => display_name,
          'description' => description,
          'url' => url,
          'auth_type' => auth_type,
          'source' => 'default'
        }.compact
      end
    end

    CONFIG_PATHS = [
      '/app/mcp/default_remote_servers.json',
      Rails.root.join('..', 'mcp', 'default_remote_servers.json'),
      Rails.root.join('mcp', 'default_remote_servers.json')
    ].freeze

    def initialize
      @servers = nil
      @loaded_at = nil
    end

    # Get all default servers
    # @return [Array<ServerConfig>]
    def list_all
      load!
      @servers.values
    end

    # Find a default server by slug name
    # @param slug [String] The slugified server name (e.g., "notion")
    # @return [ServerConfig, nil]
    def find_by_name(slug)
      load!
      @servers[slug.to_s.downcase]
    end

    # Check if a server name is a default server
    # @param slug [String] The slugified server name
    # @return [Boolean]
    def default_server?(slug)
      load!
      @servers.key?(slug.to_s.downcase)
    end

    # Get all default server names (slugs)
    # @return [Array<String>]
    def server_names
      load!
      @servers.keys
    end

    # Force reload of config (useful for testing or after config changes)
    def reload!
      @servers = nil
      @loaded_at = nil
      load!
    end

    private

    def load!
      return if @servers && cache_valid?

      @servers = {}
      config_path = find_config_path
      return unless config_path

      data = JSON.parse(File.read(config_path))
      servers_data = data['servers'] || {}

      servers_data.each do |slug, config|
        next unless config['enabled'] != false  # Default to enabled

        @servers[slug.downcase] = ServerConfig.new(
          name: slug.downcase,
          display_name: config['name'] || slug.titleize,
          description: config['description'],
          url: config['url'],
          auth_type: config['auth_type'] || 'oauth_consent',
          enabled: config['enabled'] != false,
          metadata: config.except('enabled', 'name', 'description', 'url', 'auth_type')
        )
      end

      @loaded_at = Time.current
      Rails.logger.info("[DefaultServersService] Loaded #{@servers.size} default servers")
    rescue JSON::ParserError => e
      Rails.logger.error("[DefaultServersService] Failed to parse config: #{e.message}")
      @servers = {}
    rescue => e
      Rails.logger.error("[DefaultServersService] Failed to load config: #{e.message}")
      @servers = {}
    end

    def find_config_path
      CONFIG_PATHS.find { |path| File.exist?(path) }
    end

    def cache_valid?
      return false unless @loaded_at

      # Reload every 5 minutes in development, 1 hour in production
      ttl = Rails.env.development? ? 5.minutes : 1.hour
      @loaded_at > ttl.ago
    end
  end
end
