# frozen_string_literal: true

namespace :mcp do
  desc "Validate MCP servers configuration"
  task validate_servers: :environment do
    puts "\n🔍 Validating MCP Server Configurations\n"
    puts "=" * 60

    errors = []
    warnings = []

    # Find config paths
    mcp_paths = [
      Rails.root.join('..', 'mcp'),
      Rails.root.join('mcp'),
      '/app/mcp'
    ]

    mcp_dir = mcp_paths.find { |path| Dir.exist?(path) }

    unless mcp_dir
      puts "❌ ERROR: Could not find mcp directory"
      puts "   Searched paths:"
      mcp_paths.each { |p| puts "   - #{p}" }
      exit 1
    end

    puts "✅ Found MCP directory: #{mcp_dir}\n"

    # Validate local servers (servers.json)
    servers_path = File.join(mcp_dir, 'servers.json')
    puts "\n📦 Local Servers (#{servers_path})"
    puts "-" * 40

    if File.exist?(servers_path)
      begin
        config = JSON.parse(File.read(servers_path))
        puts "✅ JSON is valid"

        servers = config['servers'] || {}
        puts "Found #{servers.count} servers\n"

        servers.each do |name, cfg|
          puts "\n  #{name}:"
          puts "    Transport: #{cfg['transport']}"
          puts "    Enabled: #{cfg['enabled'] != false}"

          if cfg['authProvider']
            auth_path = File.join(mcp_dir, cfg['authProvider'])
            if File.exist?(auth_path)
              puts "    ✅ Auth provider: #{cfg['authProvider']}"

              # Check credentials
              auth_config = JSON.parse(File.read(auth_path))
              credentials = auth_config.dig('backend', 'credentialsEnv') || []
              if credentials.any?
                missing = credentials.select { |env| ENV[env].blank? }
                if missing.any?
                  warnings << "#{name}: Missing ENV vars: #{missing.join(', ')}"
                  puts "    ⚠️  Missing ENV: #{missing.join(', ')}"
                else
                  puts "    ✅ All credentials configured"
                end
              end
            else
              errors << "#{name}: Auth provider not found: #{cfg['authProvider']}"
              puts "    ❌ Auth provider not found"
            end
          end
        end
      rescue JSON::ParserError => e
        errors << "Invalid JSON in servers.json: #{e.message}"
        puts "❌ Invalid JSON: #{e.message}"
      end
    else
      errors << "servers.json not found"
      puts "❌ File not found"
    end

    # Validate remote servers (remote_servers.json)
    remote_path = File.join(mcp_dir, 'remote_servers.json')
    puts "\n🌐 Remote Servers (#{remote_path})"
    puts "-" * 40

    if File.exist?(remote_path)
      begin
        config = JSON.parse(File.read(remote_path))
        puts "✅ JSON is valid"

        servers = config['servers'] || {}
        puts "Found #{servers.count} servers\n"

        servers.each do |name, cfg|
          puts "\n  #{name}:"
          puts "    ✅ Name: #{cfg['name']}"
          puts "    ✅ URL: #{cfg['url']}"
          puts "    ✅ Auth: #{cfg['auth_type']}"
          puts "    ✅ Transport: #{cfg['transport'] || 'http'}"
        end
      rescue JSON::ParserError => e
        errors << "Invalid JSON in remote_servers.json: #{e.message}"
        puts "❌ Invalid JSON: #{e.message}"
      end
    else
      puts "ℹ️  No remote_servers.json found (optional)"
    end

    # Summary
    puts "\n" + "=" * 60
    puts "📊 VALIDATION SUMMARY"
    puts "=" * 60

    if errors.any?
      puts "\n❌ ERRORS (#{errors.count}):"
      errors.each { |e| puts "   - #{e}" }
    end

    if warnings.any?
      puts "\n⚠️  WARNINGS (#{warnings.count}):"
      warnings.each { |w| puts "   - #{w}" }
    end

    if errors.empty? && warnings.empty?
      puts "\n✅ All configurations validated successfully!"
    elsif errors.empty?
      puts "\n✅ Validation passed (with #{warnings.count} warnings)"
    else
      puts "\n❌ Validation failed with #{errors.count} errors"
      exit 1
    end
  end

  desc "Test MCP server model and integration"
  task test_integration: :environment do
    puts "\n🧪 Testing MCP Server Integration\n"
    puts "=" * 60

    errors = []

    # Test 1: McpServer model methods
    puts "\n1️⃣  Testing McpServer model..."
    begin
      # Create a test server in memory (don't save)
      test_server = McpServer.new(
        name: "test-server",
        transport: 'stdio',
        endpoint: 'stdio',
        healthy: true,
        metadata: {
          'kind' => 'local',
          'display_name' => 'Test Server',
          'description' => 'A test server',
          'category' => 'Test',
          'icon' => 'test',
          'enabled' => true
        }
      )

      # Test methods
      if test_server.display_name == 'Test Server'
        puts "   ✅ display_name method works"
      else
        errors << "display_name method failed"
        puts "   ❌ display_name method failed"
      end

      if test_server.kind == 'local'
        puts "   ✅ kind method works"
      else
        errors << "kind method failed"
        puts "   ❌ kind method failed"
      end

      if test_server.local? && !test_server.remote?
        puts "   ✅ local?/remote? methods work"
      else
        errors << "local?/remote? methods failed"
        puts "   ❌ local?/remote? methods failed"
      end

      config_status = test_server.configuration_status
      if config_status[:configured] == true
        puts "   ✅ configuration_status method works"
      else
        errors << "configuration_status method failed"
        puts "   ❌ configuration_status method failed"
      end

      puts "   ℹ️  (Test server not persisted)"
    rescue => e
      errors << "McpServer model error: #{e.message}"
      puts "   ❌ #{e.message}"
    end

    # Test 2: ConnectionManager
    puts "\n2️⃣  Testing ConnectionManager..."
    begin
      Mcp::ConnectionManager.instance.reload!
      servers = Mcp::ConnectionManager.instance.list_servers
      puts "   ✅ ConnectionManager loaded #{servers.count} servers"
    rescue => e
      errors << "ConnectionManager error: #{e.message}"
      puts "   ❌ #{e.message}"
    end

    # Test 3: Database servers
    puts "\n3️⃣  Testing database servers..."
    begin
      db_servers = McpServer.all
      puts "   ✅ Found #{db_servers.count} servers in database"

      local_configured = db_servers.select { |s| s.local? && s.configured? }
      local_unconfigured = db_servers.select { |s| s.local? && !s.configured? }
      remote = db_servers.select(&:remote?)

      puts "   ℹ️  Local configured: #{local_configured.count}"
      puts "   ℹ️  Local unconfigured: #{local_unconfigured.count}"
      puts "   ℹ️  Remote: #{remote.count}"
    rescue => e
      errors << "Database servers error: #{e.message}"
      puts "   ❌ #{e.message}"
    end

    # Summary
    puts "\n" + "=" * 60
    puts "📊 INTEGRATION TEST SUMMARY"
    puts "=" * 60

    if errors.empty?
      puts "\n✅ All integration tests passed!"
    else
      puts "\n❌ #{errors.count} tests failed:"
      errors.each { |e| puts "   - #{e}" }
      exit 1
    end
  end

  desc "List all configured MCP servers"
  task list: :environment do
    puts "\n📋 MCP Servers Overview\n"
    puts "=" * 60

    # Reload config
    Mcp::ConnectionManager.instance.reload!

    # Local servers
    puts "\n🖥️  Local Servers:"
    puts "-" * 40

    local_servers = McpServer.all.select(&:local?)
    configured = local_servers.select(&:configured?)
    unconfigured = local_servers.reject(&:configured?)

    if configured.any?
      puts "\n  Configured (#{configured.count}):"
      configured.each do |server|
        health = server.healthy ? '🟢' : '🔴'
        puts "    #{health} #{server.display_name}"
        puts "       Tools: #{server.tools_cache&.size || 0}"
        puts "       Category: #{server.category}"
      end
    end

    if unconfigured.any?
      puts "\n  Needs Setup (#{unconfigured.count}):"
      unconfigured.each do |server|
        puts "    🟡 #{server.display_name}"
        config = server.configuration_status
        if config[:missing]&.any?
          puts "       Missing: #{config[:missing].join(', ')}"
        end
      end
    end

    # Remote servers
    puts "\n🌐 Remote Servers:"
    puts "-" * 40

    remote_servers = McpServer.all.select(&:remote?)
    if remote_servers.any?
      remote_servers.each do |server|
        puts "  🟢 #{server.display_name}"
        puts "     URL: #{server.endpoint}"
      end
    else
      puts "  (No remote servers configured)"
    end

    # Database remote servers (user-added)
    if defined?(RemoteMcpServer) && RemoteMcpServer.any?
      puts "\n💾 User-Added Remote Servers:"
      puts "-" * 40
      RemoteMcpServer.find_each do |server|
        connections = server.user_mcp_connections.count
        puts "  #{server.name}"
        puts "     URL: #{server.url}"
        puts "     Connections: #{connections}"
      end
    end
  end

  desc "Run all MCP server tests"
  task test_all: [:validate_servers, :test_integration] do
    puts "\n" + "=" * 60
    puts "🎉 All MCP server tests completed!"
    puts "=" * 60
  end

  desc "Clean up stale MCP server references in goals"
  task cleanup_goals: :environment do
    puts "\n🧹 Cleaning up stale MCP server references in goals\n"

    valid = McpServer.valid_names
    puts "Valid servers: #{valid.join(', ')}\n\n"

    cleaned_count = 0
    Goal.find_each do |goal|
      next if goal.enabled_mcp_servers.blank?

      original = goal.enabled_mcp_servers
      cleaned = original.select { |name| valid.include?(name.downcase) }

      if cleaned != original
        stale = original - cleaned
        puts "Goal #{goal.id} (#{goal.title}): removing #{stale.join(', ')}"
        goal.update_column(:enabled_mcp_servers, cleaned)
        cleaned_count += 1
      end
    end

    puts "\n✅ Cleaned #{cleaned_count} goals"
  end
end
