# frozen_string_literal: true

class Api::HealthController < Api::BaseController
  skip_before_action :authenticate_user!, only: [:show, :system, :streams]
  # GET /api/health/streams
  def streams
    stats = Streams::Broker.connection_stats
    render json: {
      active_subscriptions: stats[:active_subscriptions],
      total_channels: stats[:total_channels],
      stale_connections: stats[:stale_connections],
      cleanup_thread_alive: stats[:cleanup_thread_alive],
      timestamp: Time.current.iso8601
    }
  end

  # GET /api/health/system
  def system
    render json: {
      rails_env: Rails.env,
      database_connected: database_connected?,
      redis_connected: redis_connected?,
      memory_usage: memory_usage_mb,
      thread_count: Thread.list.count,
      timestamp: Time.current.iso8601
    }
  end

  # GET /api/health - Overall health check with status codes
  # Returns 200 (healthy), 200 (degraded), or 503 (unhealthy)
  def show
    checks = {
      database: check_database,
      redis: check_redis,
      sidekiq: check_sidekiq
    }

    all_healthy = checks.values.all? { |check| check[:status] == 'healthy' }
    any_unhealthy = checks.values.any? { |check| check[:status] == 'unhealthy' }

    overall_status = if any_unhealthy
      'unhealthy'
    elsif all_healthy
      'healthy'
    else
      'degraded'
    end

    status_code = overall_status == 'unhealthy' ? 503 : 200

    render json: {
      status: overall_status,
      timestamp: Time.current.iso8601,
      checks: checks
    }, status: status_code
  end

  private

  def database_connected?
    ActiveRecord::Base.connection.active?
  rescue
    false
  end

  def redis_connected?
    Redis.new(url: ENV['REDIS_URL'].presence || 'redis://redis:6379/0').ping == 'PONG'
  rescue
    false
  end

  def memory_usage_mb
    `ps -o rss= -p #{Process.pid}`.to_i / 1024
  rescue
    0
  end

  # Detailed health check methods
  def check_database
    ActiveRecord::Base.connection.execute('SELECT 1')
    { status: 'healthy', message: 'Database connected' }
  rescue => e
    Rails.logger.error("[Health] Database check failed: #{e.message}")
    { status: 'unhealthy', message: "Database error: #{e.message}" }
  end

  def check_redis
    redis_url = ENV['REDIS_URL'].presence || 'redis://redis:6379/0'
    redis = Redis.new(url: redis_url)
    redis.ping
    { status: 'healthy', message: 'Redis connected' }
  rescue => e
    Rails.logger.error("[Health] Redis check failed: #{e.message}")
    { status: 'unhealthy', message: "Redis error: #{e.message}" }
  end

  # Check Sidekiq health - catches orchestrator failures and other job issues
  # High retry/dead counts indicate something is repeatedly failing
  def check_sidekiq
    return { status: 'healthy', message: 'No Sidekiq available' } unless defined?(Sidekiq)

    require 'sidekiq/api'
    stats = Sidekiq::Stats.new
    retry_size = Sidekiq::RetrySet.new.size
    dead_size = Sidekiq::DeadSet.new.size
    failed = stats.failed

    # Dead jobs mean permanent failures (e.g., orchestrator hitting encryption errors)
    if dead_size > 50
      Rails.logger.error("[Health] High dead job count: #{dead_size}")
      return { status: 'unhealthy', message: "#{dead_size} dead jobs (permanent failures)" }
    end

    # High retry queue means jobs are failing repeatedly
    if retry_size > 100
      Rails.logger.warn("[Health] High retry queue size: #{retry_size}")
      return { status: 'degraded', message: "#{retry_size} jobs retrying" }
    end

    # Show recent failure count to help detect trends
    message = "#{retry_size} retrying, #{dead_size} dead"
    message += ", #{failed} total failed" if failed > 0

    { status: 'healthy', message: message }
  rescue => e
    Rails.logger.error("[Health] Sidekiq check failed: #{e.message}")
    { status: 'degraded', message: "Could not check Sidekiq: #{e.message}" }
  end
end
