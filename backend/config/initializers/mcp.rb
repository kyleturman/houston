# frozen_string_literal: true

# Load MCP services on Rails initialization
Rails.application.config.to_prepare do
  require Rails.root.join('app/services/mcp/connection_manager')
  require Rails.root.join('app/services/mcp/server')
  require Rails.root.join('app/services/mcp/stdio_client')
  require Rails.root.join('app/services/mcp/json_rpc')
end

# Pre-warm MCP servers after Rails initialization to avoid cold start delays
# This runs in a background thread to not block server startup
Rails.application.config.after_initialize do
  Thread.new do
    sleep 2 # Wait for Rails to fully initialize
    begin
      Rails.logger.info("[MCP] Pre-warming MCP servers...")
      start_time = Time.now
      Mcp::ConnectionManager.instance.load!
      tools_count = Mcp::ConnectionManager.instance.list_tools.length
      elapsed = ((Time.now - start_time) * 1000).round
      Rails.logger.info("[MCP] Pre-warming complete: #{tools_count} tools in #{elapsed}ms")
    rescue => e
      Rails.logger.error("[MCP] Failed to pre-warm servers: #{e.message}")
    end
  end
end

# Pre-warm MCP servers when Sidekiq workers start
# Sidekiq runs in separate processes, so each worker needs its own warm cache
if defined?(Sidekiq)
  Sidekiq.configure_server do |config|
    config.on(:startup) do
      Rails.logger.info("[Sidekiq] Pre-warming MCP servers...")
      start_time = Time.now
      begin
        Mcp::ConnectionManager.instance.load!
        tools_count = Mcp::ConnectionManager.instance.list_tools.length
        elapsed = ((Time.now - start_time) * 1000).round
        Rails.logger.info("[Sidekiq] MCP servers warmed: #{tools_count} tools in #{elapsed}ms")
      rescue => e
        Rails.logger.error("[Sidekiq] Failed to pre-warm MCP servers: #{e.message}")
      end
    end
  end
end
