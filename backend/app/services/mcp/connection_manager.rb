# frozen_string_literal: true

require 'singleton'
require 'json'

module Mcp
  # Tracks available MCP servers and their tools.
  # Local stdio servers are configured via mcp/servers.json
  # Remote HTTP/SSE servers are configured via DB models (RemoteMcpServer, UserMcpConnection)
  class ConnectionManager
    include Singleton

    ServerRecord = Struct.new(:name, :server, :kind, keyword_init: true)

    def initialize
      @mutex = Mutex.new
      @servers = {} # name => ServerRecord
      @loaded = false
    end

    def load!
      return if @loaded
      @mutex.synchronize do
        load_local_config!
        load_remote_config!
        @loaded = true
      end
      cleanup_stale_servers!
    end

    def reload!
      @mutex.synchronize do
        @servers.clear
        @loaded = false
      end
      load!
      cleanup_stale_servers!
    end

    def list_servers
      load!
      McpServer.order(:name).map do |db|
        {
          name: db.name,
          tools: Array(db.tools_cache).map { |t| t['name'] || t[:name] }.compact,
          endpoint: db.endpoint,
          healthy: !!db.healthy
        }
      end
    end

    def list_tools
      load!
      McpServer.all.flat_map { |db| Array(db.tools_cache) }
    end

    def tool_metadata(name)
      load!
      McpServer.all.each do |db|
        md = Array(db.tools_cache).find { |t| (t['name'] || t[:name]) == name.to_s }
        return md if md
      end
      nil
    end

    def server_for_tool(name)
      load!
      # Route by first DB entry that has this tool
      McpServer.all.each do |db|
        if Array(db.tools_cache).any? { |t| (t['name'] || t[:name]) == name.to_s }
          # Case-insensitive lookup in @servers
          return @servers[db.name.downcase]&.server
        end
      end
      nil
    end

    def server_name_for_tool(name)
      load!
      # Return the server name (from DB) that owns this tool
      McpServer.all.each do |db|
        if Array(db.tools_cache).any? { |t| (t['name'] || t[:name]) == name.to_s }
          return db.name
        end
      end
      nil
    end

    def has_tool?(name)
      load!
      McpServer.all.any? do |db|
        Array(db.tools_cache).any? { |t| (t['name'] || t[:name]) == name.to_s }
      end
    end

    # Rate limit retry configuration for MCP tools
    MCP_RATE_LIMIT_RETRIES = 3
    MCP_RATE_LIMIT_BASE_DELAY = 1.5 # seconds

    def call_tool(name, user: nil, **params)
      load!
      server = server_for_tool(name)
      return { 'error' => "Tool #{name} not found", 'isError' => true } unless server

      # Sanitize search queries for common LLM spacing issues
      if name.to_s.include?('search') && params[:query].present?
        params = params.dup
        params[:query] = sanitize_search_query(params[:query])
      end

      retries = 0
      begin
        Rails.logger.info("[MCP] Calling tool '#{name}' with params: #{sanitize_for_logging(params)}")
        result = server.invoke_tool(name, args: params, user: user)
        Rails.logger.info("[MCP] Tool '#{name}' result: #{sanitize_for_logging(result)[0..500]}")

        # Check if result contains a rate limit error (Brave API returns this in content)
        if rate_limited_response?(result)
          raise RateLimitError, "Rate limit exceeded for #{name}"
        end

        result
      rescue RateLimitError => e
        retries += 1
        if retries <= MCP_RATE_LIMIT_RETRIES
          delay = MCP_RATE_LIMIT_BASE_DELAY * retries
          Rails.logger.warn("[MCP] Rate limit hit for '#{name}', retry #{retries}/#{MCP_RATE_LIMIT_RETRIES} after #{delay}s")
          sleep(delay)
          retry
        else
          Rails.logger.error("[MCP] Rate limit retries exhausted for '#{name}'")
          { 'error' => "Rate limit exceeded after #{MCP_RATE_LIMIT_RETRIES} retries", 'isError' => true }
        end
      rescue => e
        Rails.logger.error("[MCP] Tool '#{name}' call failed: #{e.class}: #{e.message}")
        Rails.logger.error("[MCP] Backtrace: #{e.backtrace.first(5).join("\n")}")
        { 'error' => e.message, 'isError' => true }
      end
    end

    # Custom error for rate limiting
    class RateLimitError < StandardError; end

    # Public method to register a remote server (called by UrlServerService)
    def register_remote_server(name, url, metadata = {})
      # Normalize name for case-insensitive lookup
      normalized_name = name.to_s.downcase

      # Create a Server object that can invoke tools via HTTP
      server = Mcp::Server.new(
        name: normalized_name,
        endpoint: url,
        transport: 'http',
        manifest: {}
      )
      @servers[normalized_name] = ServerRecord.new(name: normalized_name, server: server, kind: :remote)
    end

    private

    # Sanitize search queries for common LLM spacing issues
    # Fixes patterns like "blog2024" → "blog 2024", "2025baby" → "2025 baby"
    def sanitize_search_query(query)
      return query unless query.is_a?(String)

      sanitized = query.dup

      # Add space between word and 4-digit year: "blog2024" → "blog 2024"
      sanitized.gsub!(/([a-zA-Z])(20\d{2})/, '\1 \2')

      # Add space between 4-digit year and word: "2025baby" → "2025 baby"
      sanitized.gsub!(/(20\d{2})([a-zA-Z])/, '\1 \2')

      # Add space between word and single digit (for "4 months" etc): "newsletter4" → "newsletter 4"
      sanitized.gsub!(/([a-zA-Z])(\d)(?!\d)/, '\1 \2')

      if sanitized != query
        Rails.logger.info("[MCP] Sanitized search query: '#{query}' → '#{sanitized}'")
      end

      sanitized
    end

    # Check if MCP response indicates rate limiting
    def rate_limited_response?(result)
      return false unless result.is_a?(Hash)

      # Check content array for rate limit errors (Brave API format)
      if result['content'].is_a?(Array) && result['content'].first.is_a?(Hash)
        content_text = result['content'].first['text'].to_s
        return true if content_text.include?('429') || content_text.include?('RATE_LIMITED') || content_text.include?('rate limit')
      end

      # Check isError flag with rate limit in error message
      if result['isError'] && result['error'].to_s.include?('rate')
        return true
      end

      false
    end

    # Sanitize data for logging to prevent sensitive information exposure
    # Redacts common sensitive field patterns
    SENSITIVE_FIELDS = %w[password token secret key auth credential api_key access_token refresh_token].freeze

    def sanitize_for_logging(data)
      return data.inspect unless data.is_a?(Hash)

      sanitized = data.transform_values do |value|
        if value.is_a?(Hash)
          sanitize_hash(value)
        elsif value.is_a?(Array)
          value.map { |v| v.is_a?(Hash) ? sanitize_hash(v) : v }
        else
          value
        end
      end

      sanitize_hash(sanitized).inspect
    end

    def sanitize_hash(hash)
      hash.transform_keys(&:to_s).each_with_object({}) do |(key, value), result|
        if SENSITIVE_FIELDS.any? { |field| key.downcase.include?(field) }
          result[key] = '[REDACTED]'
        elsif value.is_a?(Hash)
          result[key] = sanitize_hash(value)
        else
          result[key] = value
        end
      end
    end

    # Pre-warm MCP servers to avoid cold start delays on first use
    # This is called during Rails initialization (see config/initializers/mcp.rb)
    def prewarm!
      load!
      Rails.logger.info("[MCP] Pre-warming MCP servers...")
      
      @servers.each do |name, record|
        next unless record.kind == :local # Only prewarm local stdio servers
        
        begin
          # Make a simple health check to start the process
          server = record.server
          server.healthy?
          Rails.logger.info("[MCP] Pre-warmed #{name} successfully")
        rescue => e
          Rails.logger.warn("[MCP] Failed to pre-warm #{name}: #{e.message}")
        end
      end
    end

    private

    LOCAL_CONFIG = '/app/mcp/servers.json'
    REMOTE_CONFIG = '/app/mcp/default_remote_servers.json'

    def load_local_config!
      return unless File.exist?(LOCAL_CONFIG)
      data = JSON.parse(File.read(LOCAL_CONFIG)) rescue {}
      servers = data['servers'] || {}
      mcp_dir = File.dirname(LOCAL_CONFIG)

      servers.each do |name, cfg|
        transport = (cfg['transport'] || 'stdio').to_s

        # Extract metadata (auth provider, connection strategy, display info, token config)
        metadata = {
          'auth_provider' => cfg['authProvider'],
          'auth_scope' => cfg['authScope'],
          'connectionStrategy' => cfg['connectionStrategy'] || 'single',
          'display_name' => cfg['name'],
          'description' => cfg['description'],
          'token_path' => cfg['tokenPath'],
          'token_format' => cfg['tokenFormat']  # Can be a hash template or nil
        }.compact

        # Check if server is configured (has all required credentials)
        configured = check_credentials_configured(mcp_dir, cfg['authProvider'])

        # If not configured, just register it in DB without connecting (available with setup)
        unless configured
          upsert_db(name: name, endpoint: 'stdio', healthy: false, tools: [], metadata: metadata, kind: :local)
          next
        end

        case transport
        when 'stdio'
          command = cfg['command'] || 'node'
          args = Array(cfg['args'] || [])
          env = (cfg['env'] || {}).transform_values { |v| substitute_env(v) }
          server = Mcp::Server.new(name: name, endpoint: nil, transport: 'stdio', command: [command, *args], base_env: env, manifest: {})
          register_and_probe!(name, server, endpoint: 'stdio', kind: :local, metadata: metadata)
        when 'http'
          endpoint = substitute_env(cfg['url'] || cfg['endpoint'] || '')
          next if endpoint.blank?
          env = (cfg['env'] || {}).transform_values { |v| substitute_env(v) }
          server = Mcp::Server.new(name: name, endpoint: endpoint, transport: 'http', base_env: env, manifest: {})
          register_and_probe!(name, server, endpoint: endpoint, kind: :local, metadata: metadata)
        end
      end
    end

    def check_credentials_configured(mcp_dir, auth_provider_path)
      return true if auth_provider_path.blank? || auth_provider_path == 'auth-providers/none.json'

      auth_path = File.join(mcp_dir, auth_provider_path)
      return false unless File.exist?(auth_path)

      auth_config = JSON.parse(File.read(auth_path)) rescue {}

      # Check for credentials file first
      if (creds_file = auth_config.dig('backend', 'credentialsFile'))
        creds_path = File.join(mcp_dir, creds_file)
        return File.exist?(creds_path)
      end

      # Fall back to env vars
      credentials = auth_config.dig('backend', 'credentialsEnv') || []
      return true if credentials.empty?

      # All required credentials must be present and non-empty
      credentials.all? { |env_var| ENV[env_var].present? }
    end

    def load_remote_config!
      # Load default remote servers from JSON config (read at runtime, no DB)
      DefaultServersService.instance.list_all.each do |default_server|
        next unless default_server.url.present?

        metadata = {
          'display_name' => default_server.display_name,
          'description' => default_server.description,
          'auth_type' => default_server.auth_type,
          'kind' => 'remote'
        }.compact

        # For remote servers, we don't probe - just register
        upsert_db(name: default_server.name, endpoint: default_server.url, healthy: true, tools: [], metadata: metadata, kind: :remote)

        # Create Server object for remote servers so tools can be called
        register_remote_server(default_server.name, default_server.url, metadata)
      end

      # Load user connections (for OAuth servers that are connected)
      load_user_connections!
    end

    def load_user_connections!
      # Load active remote connections from UserMcpConnection
      # This includes both direct (URL-only) and OAuth servers
      UserMcpConnection.remote_connections.active_connections.find_each do |conn|
        begin
          url = conn.server_url
          next unless url.present?

          name = conn.server_name
          next unless name.present?

          metadata = {
            'display_name' => conn.server_display_name,
            'auth_type' => conn.server_auth_type,
            'kind' => 'remote'
          }.compact

          # Register the server so tools can be called
          register_remote_server(name, url, metadata)

          # Update DB if this is a user-added server (not a default)
          if conn.user_added?
            upsert_db(name: name, endpoint: url, healthy: true, tools: conn.tools_cache || [], metadata: metadata, kind: :remote)
          end
        rescue ActiveRecord::Encryption::Errors::Decryption => e
          # Skip connections with corrupted encrypted data - don't let one bad record break everything
          Rails.logger.error("[MCP] Skipping connection #{conn.id} due to decryption error: #{e.message}")
        rescue => e
          Rails.logger.error("[MCP] Error loading connection #{conn.id}: #{e.class}: #{e.message}")
        end
      end
    end

    def register_and_probe!(name, server, endpoint:, kind:, metadata: {})
      @servers[name] = ServerRecord.new(name: name, server: server, kind: kind)
      tools = []
      healthy = false
      begin
        healthy = server.healthy?
        if healthy
          raw_tools = server.list_tools
          # Handle different response formats from MCP servers
          tool_list = case raw_tools
                     when Hash
                       raw_tools['tools'] || []
                     when Array
                       raw_tools.first.is_a?(Array) ? raw_tools.first : raw_tools
                     else
                       []
                     end

          tools = Array(tool_list).map do |t|
            if t.is_a?(Hash) && t['name']
              {
                'name' => t['name'],
                'description' => t['description'] || t['title'] || '',
                'params_hint' => t['inputSchema']&.dig('properties')&.keys&.join(', ') || '',
                'input_schema' => t['inputSchema']  # Store full schema for LLM tool calls
              }
            end
          end.compact
        end
        upsert_db(name: name, endpoint: endpoint, healthy: healthy, tools: tools, metadata: metadata, kind: kind)
      rescue => e
        Rails.logger.warn("[Mcp::ConnectionManager] probe failed for #{name}: #{e.class}: #{e.message}")
        upsert_db(name: name, endpoint: endpoint, healthy: false, tools: [], metadata: metadata, kind: kind)
      end
    end

    def upsert_db(name:, endpoint:, healthy:, tools: [], metadata: {}, kind: :local)
      # Names are slugified by the model callback, so direct lookup works
      name_slug = name.to_s.downcase
      rec = McpServer.find_by(name: name_slug) || McpServer.new(name: name_slug)
      rec.transport = endpoint == 'stdio' ? 'stdio' : 'http'
      rec.endpoint = endpoint
      rec.healthy = healthy
      rec.last_seen_at = Time.current
      # Only overwrite tools_cache if new tools are provided (preserve existing if empty)
      rec.tools_cache = tools if tools.present? || rec.tools_cache.blank?
      rec.metadata = (rec.metadata || {}).merge(metadata).merge('kind' => kind.to_s)
      rec.save!
    end

    def substitute_env(val)
      return val unless val.is_a?(String)
      val.gsub(/\$\{([A-Z0-9_]+)\}/) { |m| ENV[$1].to_s }
    end

    def cleanup_stale_servers!
      # Collect valid server names from config files and user connections
      valid_names = Set.new

      # From local servers.json
      if File.exist?(LOCAL_CONFIG)
        data = JSON.parse(File.read(LOCAL_CONFIG)) rescue {}
        (data['servers'] || {}).each_key { |name| valid_names << name.downcase }
      end

      # From default remote servers (JSON config loaded at runtime)
      DefaultServersService.instance.server_names.each { |name| valid_names << name }

      # From active user connections (user-added servers)
      UserMcpConnection.remote_connections.active_connections.each do |conn|
        valid_names << conn.server_name if conn.server_name.present?
      end

      # Delete any McpServer entries not in valid_names (names are already slugified/lowercase)
      # Guard: don't delete everything if all config sources are empty
      if valid_names.empty?
        Rails.logger.warn("[MCP] No valid server names found - skipping cleanup to prevent accidental deletion")
        return
      end

      stale = McpServer.where.not(name: valid_names.to_a)
      if stale.any?
        Rails.logger.info("[MCP] Cleaning up #{stale.count} stale servers: #{stale.pluck(:name).join(', ')}")
        stale.destroy_all
      end
    end
  end
end
