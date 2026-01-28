#!/usr/bin/env ruby
# frozen_string_literal: true

# CLI Status Display - Shows same stats as admin dashboard
require 'io/console'

class StatusDisplay
  COLORS = {
    reset: "\e[0m",
    bold: "\e[1m",
    green: "\e[32m",
    red: "\e[31m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    gray: "\e[90m"
  }

  def self.run
    new.display
  end

  def display
    header
    puts

    system_health
    puts

    sidekiq_stats
    puts

    llm_provider_health
    puts

    llm_costs
    puts

    user_stats
    puts

    mcp_servers
    puts

    database_stats
    puts

    footer
  end

  private

  def header
    puts colorize("=" * width, :cyan)
    puts colorize("  Houston - System Status", :bold)
    puts colorize("  #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}", :gray)
    puts colorize("=" * width, :cyan)
  end

  def footer
    puts colorize("=" * width, :cyan)
    puts colorize("  View full dashboard: http://localhost:#{ENV.fetch('PORT', 3033)}", :gray)
    puts colorize("=" * width, :cyan)
  end

  def system_health
    puts colorize("System Health", :bold)
    puts colorize("-" * width, :gray)

    postgres = check_postgres
    redis = check_redis
    sidekiq = check_sidekiq

    status_line("PostgreSQL", postgres)
    status_line("Redis", redis)
    status_line("Sidekiq", sidekiq, sidekiq ? "#{Sidekiq::ProcessSet.new.size} process(es)" : nil)
  end

  def sidekiq_stats
    return unless check_sidekiq

    puts colorize("Background Jobs", :bold)
    puts colorize("-" * width, :gray)

    stats = Sidekiq::Stats.new
    stat_line("Processed", format_number(stats.processed))
    stat_line("Enqueued", format_number(stats.enqueued), :blue)
    stat_line("Failed", format_number(stats.failed), :red)
    stat_line("Scheduled", format_number(stats.scheduled_size), :yellow)
    stat_line("Retry Queue", format_number(stats.retry_size), :yellow)
    stat_line("Dead Queue", format_number(stats.dead_size), :gray)
  rescue => e
    puts colorize("  Error: #{e.message}", :red)
  end

  def llm_provider_health
    puts colorize("LLM Provider Configuration", :bold)
    puts colorize("-" * width, :gray)

    begin
      health = Llms::HealthCheck.check_configuration

      # Check each use case
      [:agents, :tasks, :summaries].each do |use_case|
        result = health[use_case]
        status = result.healthy?

        if status
          status_line(use_case.to_s.capitalize, true, result.message)
        else
          status_line(use_case.to_s.capitalize, false, result.message)
        end
      end

      # Provider availability with live connectivity
      puts colorize("  Available Providers:", :gray)
      providers = Llms::HealthCheck.provider_summary
      connectivity = Llms::HealthCheck.connectivity_status

      providers.each do |provider, info|
        status_indicator = case info[:api_key_status]
                          when :healthy then colorize("✓", :green)
                          when :warning then colorize("⚠", :yellow)
                          else colorize("○", :gray)
                          end

        configured_badge = info[:configured] ? colorize(" [IN USE]", :green) : ""
        usage = info[:used_in].any? ? " (#{info[:used_in].join(', ')})" : ""

        puts "    #{status_indicator} #{provider.to_s.ljust(15)} #{info[:api_key_message]}#{configured_badge}#{usage}"

        # Show connectivity status if available
        conn = connectivity[provider]
        if conn
          if conn[:status] == 'healthy'
            status_msg = colorize("✓ Connected (#{conn[:duration_ms]}ms, #{conn[:success_count]} calls)", :green)
            source_msg = conn[:source] == 'usage' ? 'live' : 'startup test'
            puts "      #{status_msg} - #{source_msg}"
          elsif conn[:status] == 'unhealthy'
            puts "      #{colorize("✗ #{conn[:last_error]}", :red)} (#{conn[:failure_count]} failures)"
          end
        end
      end

      # Recent activity
      recent = Llms::HealthCheck.check_recent_errors
      if recent[:total_calls] && recent[:total_calls] > 0
        puts colorize("  Recent Activity (24h):", :gray)
        puts "    Total Calls: #{colorize(format_number(recent[:total_calls]), :cyan)}"
      end
    rescue => e
      puts colorize("  Error: #{e.message}", :red)
    end
  end

  def llm_costs
    puts colorize("LLM Costs", :bold)
    puts colorize("-" * width, :gray)

    total_cost = LlmCost.sum(:cost)
    stat_line("Total Cost", format_cost(total_cost), :magenta)

    # By provider
    by_provider = LlmCost.group(:provider).sum(:cost)
    if by_provider.any?
      puts colorize("  By Provider:", :gray)
      by_provider.each do |provider, cost|
        puts "    #{provider.ljust(15)} #{colorize(format_cost(cost), :magenta)}"
      end
    end

    # Top models
    by_model = LlmCost.group(:model).sum(:cost).sort_by { |_, v| -v }.first(5)
    if by_model.any?
      puts colorize("  Top 5 Models:", :gray)
      by_model.each do |model, cost|
        puts "    #{model.ljust(30)} #{colorize(format_cost(cost), :magenta)}"
      end
    end

    # Token stats
    input_tokens = LlmCost.sum(:input_tokens)
    output_tokens = LlmCost.sum(:output_tokens)
    cached_tokens = LlmCost.sum(:cached_tokens)

    puts colorize("  Tokens:", :gray)
    puts "    Input:  #{colorize(format_number(input_tokens), :cyan)}"
    puts "    Output: #{colorize(format_number(output_tokens), :cyan)}"
    puts "    Cached: #{colorize(format_number(cached_tokens), :green)}"

    # Daily cost (last 7 days)
    seven_days_ago = 7.days.ago
    daily_costs = LlmCost
      .where('created_at >= ?', seven_days_ago)
      .group("DATE(created_at)")
      .sum(:cost)
      .sort_by { |k, _| k }

    if daily_costs.any?
      puts colorize("  Last 7 Days:", :gray)
      daily_costs.last(7).each do |date, cost|
        puts "    #{date} #{colorize(format_cost(cost), :magenta)}"
      end
    end
  rescue => e
    puts colorize("  Error: #{e.message}", :red)
  end

  def user_stats
    puts colorize("Users & Agents", :bold)
    puts colorize("-" * width, :gray)

    total_users = User.count
    active_goals = Goal.where(status: :working).count
    active_tasks = AgentTask.where(status: :active).count

    stat_line("Total Users", format_number(total_users))
    stat_line("Active Goals", format_number(active_goals), :green)
    stat_line("Active Tasks", format_number(active_tasks), :green)
    stat_line("Active Agents", format_number(active_goals + active_tasks), :yellow)

    # Top users by cost
    top_users = User.joins(:llm_costs)
      .select('users.email, SUM(llm_costs.cost) as total_cost')
      .group('users.id, users.email')
      .order('total_cost DESC')
      .limit(5)

    if top_users.any?
      puts colorize("  Top 5 Users by Cost:", :gray)
      top_users.each do |user|
        email = user.email.length > 30 ? "#{user.email[0..27]}..." : user.email
        puts "    #{email.ljust(35)} #{colorize(format_cost(user.total_cost), :magenta)}"
      end
    end
  rescue => e
    puts colorize("  Error: #{e.message}", :red)
  end

  def mcp_servers
    puts colorize("MCP Servers", :bold)
    puts colorize("-" * width, :gray)

    total = McpServer.count
    healthy = McpServer.where(healthy: true).count
    unhealthy = total - healthy

    stat_line("Total Servers", format_number(total))
    stat_line("Healthy", format_number(healthy), :green)
    stat_line("Unhealthy", format_number(unhealthy), unhealthy > 0 ? :red : :gray)

    servers = McpServer.all
    if servers.any?
      puts colorize("  Servers:", :gray)
      servers.each do |server|
        status_indicator = server.healthy ? colorize("●", :green) : colorize("●", :red)
        tools = server.tools_cache&.size || 0
        connections = UserMcpConnection.where(mcp_server_id: server.id, status: 'active').count
        puts "    #{status_indicator} #{server.name.ljust(20)} #{tools} tools, #{connections} connections"
      end
    end
  rescue => e
    puts colorize("  Error: #{e.message}", :red)
  end

  def database_stats
    puts colorize("Database Statistics", :bold)
    puts colorize("-" * width, :gray)

    stats = {
      'Users' => User.count,
      'Goals' => Goal.count,
      'Tasks' => AgentTask.count,
      'Notes' => Note.count,
      'Thread Messages' => ThreadMessage.count,
      'Feeds' => Feed.count,
      'LLM Costs' => LlmCost.count
    }

    stats.each do |label, count|
      stat_line(label, format_number(count))
    end
  rescue => e
    puts colorize("  Error: #{e.message}", :red)
  end

  # Helper methods

  def check_postgres
    ActiveRecord::Base.connection.execute("SELECT 1").any?
    true
  rescue
    false
  end

  def check_redis
    Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')).ping == 'PONG'
  rescue
    false
  end

  def check_sidekiq
    Sidekiq::ProcessSet.new.size > 0
  rescue
    false
  end

  def status_line(label, status, detail = nil)
    indicator = status ? colorize("✓", :green) : colorize("✗", :red)
    status_text = status ? colorize("OK", :green) : colorize("DOWN", :red)
    detail_text = detail ? " (#{detail})" : ""
    puts "  #{indicator} #{label.ljust(20)} #{status_text}#{detail_text}"
  end

  def stat_line(label, value, color = :reset)
    puts "  #{label.ljust(20)} #{colorize(value, color)}"
  end

  def format_number(num)
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def format_cost(amount)
    return "$0.00" if amount.nil? || amount.zero?

    if amount < 0.01
      "$#{sprintf('%.6f', amount)}"
    else
      "$#{sprintf('%.2f', amount)}"
    end
  end

  def colorize(text, color)
    return text.to_s unless STDOUT.tty?
    "#{COLORS[color]}#{text}#{COLORS[:reset]}"
  end

  def width
    @width ||= begin
      if STDOUT.tty?
        IO.console.winsize[1]
      else
        80
      end
    rescue
      80
    end
  end
end

# Run if called directly
if __FILE__ == $0
  StatusDisplay.run
end
