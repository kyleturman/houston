# frozen_string_literal: true

module Admin
  class DashboardController < Admin::BaseController
    include JwtAuth
    include MagicLinkSender
    include ServerConfig

    layout 'admin'

    def index
      @stats = {
        system: system_health,
        sidekiq: sidekiq_stats,
        llm_health: llm_health_check,
        llm_costs: llm_cost_stats,
        users: user_stats,
        mcp_servers: mcp_server_stats,
        database: database_stats,
        email_enabled: EmailConfig.enabled?
      }
    end

    def create_user
      email = params[:email]&.strip&.downcase

      if email.blank?
        render json: { success: false, message: "Email cannot be blank" }, status: :bad_request
        return
      end

      user = User.find_or_initialize_by(email: email)

      if user.new_record?
        if user.save
          # Send magic link using shared concern
          if send_magic_link(user)
            render json: { success: true, message: "User #{email} created and magic link sent!" }
          else
            render json: { success: false, message: "User created but failed to send magic link" }, status: :internal_server_error
          end
        else
          render json: { success: false, message: "Failed to create user: #{user.errors.full_messages.join(', ')}" }, status: :unprocessable_entity
        end
      else
        # Send magic link to existing user using shared concern
        if send_magic_link(user)
          render json: { success: true, message: "User #{email} already exists. Magic link sent!" }
        else
          render json: { success: false, message: "User exists but failed to send magic link" }, status: :internal_server_error
        end
      end
    rescue => e
      Rails.logger.error("[Admin] Failed to create user: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: :internal_server_error
    end

    # Create user and generate invite token (no email sent)
    def create_user_with_token
      email = params[:email]&.strip&.downcase

      if email.blank?
        render json: { success: false, message: "Email cannot be blank" }, status: :bad_request
        return
      end

      user = User.find_or_initialize_by(email: email)
      is_new = user.new_record?

      unless user.save
        render json: { success: false, message: "Failed to create user: #{user.errors.full_messages.join(', ')}" }, status: :unprocessable_entity
        return
      end

      # Create invite token (expires in 7 days by default)
      invite_token = user.invite_tokens.build(expires_at: 7.days.from_now)
      raw_token = invite_token.set_token!

      if invite_token.save
        render json: {
          success: true,
          token: raw_token,
          invite_link: build_invite_deep_link(email: email, token: raw_token),
          expires_at: invite_token.expires_at&.iso8601,
          message: is_new ? "User #{email} created" : "User #{email} already exists",
          user_id: user.id
        }
      else
        render json: { success: false, message: "User created but failed to generate invite token" }, status: :internal_server_error
      end
    rescue => e
      Rails.logger.error("[Admin] Failed to create user with token: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: :internal_server_error
    end

    def send_link
      user_id = params[:user_id]

      if user_id.blank?
        render json: { success: false, message: "User ID is required" }, status: :bad_request
        return
      end

      user = User.find_by(id: user_id)
      unless user
        render json: { success: false, message: "User not found" }, status: :not_found
        return
      end

      # Send magic link using shared concern
      if send_magic_link(user)
        render json: { success: true, message: "Magic link sent to #{user.email}" }
      else
        render json: { success: false, message: "Failed to send magic link to #{user.email}" }, status: :internal_server_error
      end
    rescue => e
      Rails.logger.error("[Admin] Failed to send link: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: :internal_server_error
    end

    def revoke_device
      device_id = params[:device_id]

      if device_id.blank?
        render json: { success: false, message: "Device ID is required" }, status: :bad_request
        return
      end

      device = Device.find_by(id: device_id)
      unless device
        render json: { success: false, message: "Device not found" }, status: :not_found
        return
      end

      user_email = device.user&.email || "Unknown"
      device.destroy
      render json: { success: true, message: "Device revoked for #{user_email}" }
    rescue => e
      Rails.logger.error("[Admin] Failed to revoke device: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: :internal_server_error
    end

    def deactivate_user
      user_id = params[:user_id]

      if user_id.blank?
        render json: { success: false, message: "User ID is required" }, status: :bad_request
        return
      end

      user = User.find_by(id: user_id)
      unless user
        render json: { success: false, message: "User not found" }, status: :not_found
        return
      end

      # Revoke all devices for this user
      devices_count = user.devices.count
      user.devices.destroy_all

      # Mark user as inactive
      user.update(active: false)

      render json: {
        success: true,
        message: "User #{user.email} deactivated. #{devices_count} device(s) revoked."
      }
    rescue => e
      Rails.logger.error("[Admin] Failed to deactivate user: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: :internal_server_error
    end

    def reactivate_user
      user_id = params[:user_id]

      if user_id.blank?
        render json: { success: false, message: "User ID is required" }, status: :bad_request
        return
      end

      user = User.find_by(id: user_id)
      unless user
        render json: { success: false, message: "User not found" }, status: :not_found
        return
      end

      # Mark user as active
      user.update(active: true)

      render json: {
        success: true,
        message: "User #{user.email} reactivated."
      }
    rescue => e
      Rails.logger.error("[Admin] Failed to reactivate user: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: :internal_server_error
    end

    def create_invite_token
      user_id = params[:user_id]
      expires_in = params[:expires_in] # '7', '15', '30', or 'never'

      if user_id.blank?
        render json: { success: false, message: "User ID is required" }, status: :bad_request
        return
      end

      user = User.find_by(id: user_id)
      unless user
        render json: { success: false, message: "User not found" }, status: :not_found
        return
      end

      # Calculate expiration
      expires_at = case expires_in
                   when '7' then 7.days.from_now
                   when '15' then 15.days.from_now
                   when '30' then 30.days.from_now
                   when 'never' then nil
                   else 7.days.from_now # default
                   end

      invite_token = user.invite_tokens.build(expires_at: expires_at)
      raw_token = invite_token.set_token!

      if invite_token.save
        render json: {
          success: true,
          token: raw_token,
          invite_link: build_invite_deep_link(email: user.email, token: raw_token),
          expires_at: expires_at&.iso8601,
          message: "Invite token created for #{user.email}"
        }
      else
        render json: { success: false, message: invite_token.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error("[Admin] Failed to create invite token: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: :internal_server_error
    end

    def revoke_invite_token
      token_id = params[:token_id]

      if token_id.blank?
        render json: { success: false, message: "Token ID is required" }, status: :bad_request
        return
      end

      invite_token = InviteToken.find_by(id: token_id)
      unless invite_token
        render json: { success: false, message: "Invite token not found" }, status: :not_found
        return
      end

      invite_token.revoke!
      render json: { success: true, message: "Invite token revoked" }
    rescue => e
      Rails.logger.error("[Admin] Failed to revoke invite token: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: :internal_server_error
    end

    private

    def system_health
      {
        postgres: postgres_healthy?,
        redis: redis_healthy?,
        sidekiq: sidekiq_healthy?,
        backend: backend_diagnostics
      }
    end

    def backend_diagnostics
      pid = Process.pid

      # BusyBox ps doesn't support -p flag, so we get all processes and filter
      # Use ps -o pid,vsz (VSZ is virtual memory size in KB, closest to RSS available in BusyBox)
      ps_output = `ps -o pid,vsz 2>&1`.strip

      # Find the line for our PID
      our_process = ps_output.lines
        .map(&:strip)
        .find { |line| line =~ /^\s*#{pid}\s+/ }

      # Extract memory (second column)
      # BusyBox ps returns VSZ with unit suffixes: 281m, 512k, etc.
      memory_mb = 0.0
      if our_process
        parts = our_process.split
        if parts.length >= 2
          vsz_str = parts[1]
          # Parse value with unit suffix (e.g., "281m", "512k", "1g")
          if vsz_str =~ /^(\d+(?:\.\d+)?)([kmg]?)$/i
            value = $1.to_f
            unit = $2.downcase
            memory_mb = case unit
                        when 'k' then value / 1024.0
                        when 'm' then value
                        when 'g' then value * 1024.0
                        else value / 1024.0  # assume KB if no unit
                        end
          end
        end
      end

      # For uptime, use process start time
      # BusyBox ps doesn't have etime, so calculate from process start time
      process_start = `ps -o pid,stat,time 2>&1 | grep "^\\s*#{pid}\\s" 2>&1`.strip

      # Since BusyBox ps is limited, use Ruby's Process info for uptime
      # Get system uptime and approximate process uptime
      uptime_seconds = 0
      if File.exist?('/proc/uptime')
        system_uptime = File.read('/proc/uptime').split.first.to_f
        # For now, use a placeholder - we can't get exact process uptime from BusyBox ps
        # Use system uptime as a rough estimate
        uptime_seconds = system_uptime.to_i
      end

      # Format uptime display based on duration
      uptime_display = if uptime_seconds < 60
        "#{uptime_seconds}s"
      elsif uptime_seconds < 3600
        "#{(uptime_seconds / 60.0).round(1)}m"
      elsif uptime_seconds < 86400
        "#{(uptime_seconds / 3600.0).round(1)}h"
      else
        days = uptime_seconds / 86400
        "#{days.round(1)}d"
      end

      {
        memory_mb: memory_mb.round(1),
        uptime: uptime_display,
        pid: pid,
        threads: Thread.list.size
      }
    rescue => e
      Rails.logger.error("[Admin] Backend diagnostics failed: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      { memory_mb: 0, uptime: '0s', pid: Process.pid, threads: 0 }
    end

    def parse_etime(etime_str)
      # Parse format: [[dd-]hh:]mm:ss
      return 0 if etime_str.blank?

      parts = etime_str.split(/[-:]/).map(&:to_i).reverse
      seconds = parts[0] || 0
      minutes = parts[1] || 0
      hours = parts[2] || 0
      days = parts[3] || 0

      (days * 86400) + (hours * 3600) + (minutes * 60) + seconds
    rescue => e
      Rails.logger.error("[Admin] Failed to parse etime '#{etime_str}': #{e.message}")
      0
    end

    def postgres_healthy?
      ActiveRecord::Base.connection.execute("SELECT 1").any?
      true
    rescue => e
      Rails.logger.error("[Admin] Postgres health check failed: #{e.message}")
      false
    end

    def redis_healthy?
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')).ping == 'PONG'
    rescue => e
      Rails.logger.error("[Admin] Redis health check failed: #{e.message}")
      false
    end

    def sidekiq_healthy?
      # Check if Sidekiq is processing jobs by checking Redis
      require 'sidekiq/api'
      Sidekiq::ProcessSet.new.size > 0
    rescue => e
      Rails.logger.error("[Admin] Sidekiq health check failed: #{e.message}")
      false
    end

    def sidekiq_stats
      require 'sidekiq/api'
      stats = Sidekiq::Stats.new

      # Calculate success percentage
      total_jobs = stats.processed + stats.failed
      success_percentage = if total_jobs > 0
        ((stats.processed.to_f / total_jobs) * 100).round(1)
      else
        100.0
      end

      {
        processed: stats.processed,
        failed: stats.failed,
        success_percentage: success_percentage,
        scheduled_size: stats.scheduled_size,
        retry_size: stats.retry_size,
        dead_size: stats.dead_size,
        processes: Sidekiq::ProcessSet.new.size,
        queues: stats.queues,
        enqueued: stats.enqueued
      }
    rescue => e
      Rails.logger.error("[Admin] Sidekiq stats failed: #{e.message}")
      { error: e.message }
    end

    def llm_health_check
      # Configuration check (fast)
      configuration = Llms::HealthCheck.check_configuration

      # Provider summary (which providers are available/used)
      providers = Llms::HealthCheck.provider_summary

      # Live connectivity status (from tracker, no API calls)
      connectivity = Llms::HealthCheck.connectivity_status

      # Recent usage stats
      recent_errors = Llms::HealthCheck.check_recent_errors

      {
        configuration: configuration,
        providers: providers,
        connectivity: connectivity,
        recent_errors: recent_errors
      }
    rescue => e
      Rails.logger.error("[Admin] LLM health check failed: #{e.message}")
      { error: e.message }
    end

    def llm_cost_stats
      total_cost = LlmCost.sum(:cost)

      # Cost by provider
      by_provider = LlmCost.group(:provider).sum(:cost)

      # Cost by model
      by_model = LlmCost.group(:model).sum(:cost).sort_by { |_, v| -v }.first(10)

      # Recent costs (last 30 days, grouped by day)
      thirty_days_ago = 30.days.ago
      daily_costs = LlmCost
        .where('created_at >= ?', thirty_days_ago)
        .group("DATE(created_at)")
        .sum(:cost)
        .sort_by { |k, _| k }

      # Token usage
      total_input_tokens = LlmCost.sum(:input_tokens)
      total_output_tokens = LlmCost.sum(:output_tokens)
      total_cached_tokens = LlmCost.sum(:cached_tokens)

      # Current month cost
      current_month_start = Date.today.beginning_of_month
      current_month_cost = LlmCost
        .where('created_at >= ?', current_month_start)
        .sum(:cost)

      # Predicted/Average monthly cost
      predicted_monthly = calculate_predicted_monthly_cost(current_month_start, current_month_cost)

      {
        total: total_cost,
        lifetime: total_cost,
        current_month: current_month_cost,
        predicted_monthly: predicted_monthly,
        by_provider: by_provider,
        by_model: by_model.to_h,
        daily_costs: daily_costs,
        tokens: {
          input: total_input_tokens,
          output: total_output_tokens,
          cached: total_cached_tokens
        }
      }
    rescue => e
      Rails.logger.error("[Admin] LLM cost stats failed: #{e.message}")
      { error: e.message }
    end

    def calculate_predicted_monthly_cost(current_month_start, current_month_cost)
      # Get all historical costs grouped by month (excluding current month)
      historical_monthly = LlmCost
        .where('created_at < ?', current_month_start)
        .group("DATE_TRUNC('month', created_at)")
        .sum(:cost)

      if historical_monthly.any?
        # We have historical data - calculate average
        avg_historical = historical_monthly.values.sum / historical_monthly.size.to_f

        # If current month is trending higher/lower, blend it in
        days_in_current_month = (Date.today - current_month_start.to_date).to_i + 1
        days_in_month = Date.today.end_of_month.day

        if days_in_current_month >= 7
          # We have at least a week of data, project current month to full month
          projected_current = (current_month_cost / days_in_current_month) * days_in_month
          # Blend historical average with current projection (weighted towards historical)
          (avg_historical * 0.7) + (projected_current * 0.3)
        else
          # Not enough data in current month, just use historical average
          avg_historical
        end
      else
        # No historical data - project based on current month
        days_in_current_month = (Date.today - current_month_start.to_date).to_i + 1
        days_in_month = Date.today.end_of_month.day

        if days_in_current_month > 0
          (current_month_cost / days_in_current_month) * days_in_month
        else
          0.0
        end
      end
    end

    def user_stats
      users = User.includes(:goals, :agent_tasks, :notes, :llm_costs, :devices, :invite_tokens)
        .select('users.*, COUNT(DISTINCT goals.id) as goals_count, COUNT(DISTINCT agent_tasks.id) as tasks_count, COUNT(DISTINCT notes.id) as notes_count')
        .left_joins(:goals, :agent_tasks, :notes)
        .group('users.id')
        .order(created_at: :desc)

      # Map users to data structure
      all_user_data = users.map do |u|
        # Safely access encrypted fields
        email_display = begin
          u.email
        rescue ActiveRecord::Encryption::Errors::Decryption
          "[Decryption Error - ID: #{u.id}]"
        end

        # Get device info
        devices = u.devices.map do |d|
          {
            id: d.id,
            name: d.name,
            platform: d.platform,
            created_at: d.created_at,
            last_used_at: d.last_used_at
          }
        end

        # Get invite token info
        invite_tokens = u.invite_tokens.map do |it|
          {
            id: it.id,
            status: it.status,
            created_at: it.created_at,
            expires_at: it.expires_at,
            first_used_at: it.first_used_at
          }
        end

        {
          id: u.id,
          email: email_display,
          created_at: u.created_at,
          goals_count: u.goals_count.to_i,
          tasks_count: u.tasks_count.to_i,
          notes_count: u.notes_count.to_i,
          total_cost: u.llm_costs.sum(:cost),
          devices: devices,
          invite_tokens: invite_tokens,
          active: u.active
        }
      end

      # Partition into active and inactive users
      active_users, inactive_users = all_user_data.partition { |u| u[:active] }

      {
        total_count: User.count,
        active_agents: active_agents_count,
        users: active_users,
        deactivated_users: inactive_users
      }
    rescue => e
      Rails.logger.error("[Admin] User stats failed: #{e.message}")
      { error: e.message }
    end

    def active_agents_count
      # Count goals/tasks that are currently working/active
      active_goals = Goal.where(status: :working).count
      active_tasks = AgentTask.where(status: :active).count
      active_goals + active_tasks
    end

    def mcp_server_stats
      # Build OAuth redirect URI for setup instructions
      oauth_redirect_uri = "#{request.base_url}/api/mcp/oauth/callback"

      all_servers = McpServer.all.map do |server|
        config_status = server.configuration_status
        auth_config = server.auth_provider_config

        {
          name: server.display_name,
          internal_name: server.name,
          transport: server.transport,
          healthy: server.healthy,
          last_seen_at: server.last_seen_at,
          tools_count: server.tools_cache&.size || 0,
          connection_count: UserMcpConnection.where(mcp_server_id: server.id, status: 'active').count,
          kind: server.kind,
          description: server.description,
          enabled: server.enabled?,
          configured: config_status[:configured],
          missing_credentials: config_status[:missing] || [],
          configuration_message: config_status[:message],
          auth_type: auth_config&.dig('type'),
          oauth_redirect_uri: oauth_redirect_uri,
          oauth_scopes: auth_config&.dig('scopes', server.metadata&.dig('auth_scope')) || auth_config&.dig('scopes', 'default')
        }
      end

      # Separate by kind and configuration status
      local_configured = all_servers.select { |s| s[:kind] == 'local' && s[:configured] }
      local_unconfigured = all_servers.select { |s| s[:kind] == 'local' && !s[:configured] }
      remote_servers = all_servers.select { |s| s[:kind] == 'remote' }

      {
        total: McpServer.count,
        healthy: McpServer.where(healthy: true).count,
        configured_count: local_configured.size,
        unconfigured_count: local_unconfigured.size,
        remote_count: remote_servers.size,
        servers: all_servers,
        local_configured: local_configured,
        local_unconfigured: local_unconfigured,
        remote_servers: remote_servers
      }
    rescue => e
      Rails.logger.error("[Admin] MCP server stats failed: #{e.message}")
      { error: e.message }
    end

    def database_stats
      # Get database size
      db_size_result = ActiveRecord::Base.connection.execute(
        "SELECT pg_size_pretty(pg_database_size(current_database())) as size"
      ).first
      db_size = db_size_result['size']

      # Get connection pool stats
      pool = ActiveRecord::Base.connection_pool
      connections_active = pool.connections.count { |c| c.in_use? }
      connections_total = pool.connections.size
      connections_available = pool.size - connections_active

      {
        users: User.count,
        goals: Goal.count,
        tasks: AgentTask.count,
        notes: Note.count,
        llm_costs: LlmCost.count,
        thread_messages: ThreadMessage.count,
        size: db_size,
        connections: {
          active: connections_active,
          total: connections_total,
          available: connections_available,
          pool_size: pool.size
        }
      }
    rescue => e
      Rails.logger.error("[Admin] Database stats failed: #{e.message}")
      { error: e.message }
    end

  end
end
