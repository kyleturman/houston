#!/bin/sh
# Health check for Sidekiq
#
# Verifies Sidekiq can:
# 1. Connect to Redis
# 2. Write to Redis (schedule a test job)
# 3. Sidekiq process is running
# 4. Cron jobs are enqueuing (heartbeat check)
#
# Exit codes:
#   0 = healthy
#   1 = unhealthy

set -e

REDIS_URL="${REDIS_URL:-redis://redis:6379/0}"

# Test 1: Is the Sidekiq process running?
if ! pgrep -f "sidekiq" > /dev/null 2>&1; then
    echo "UNHEALTHY: Sidekiq process not running"
    exit 1
fi

# Test 2: Can we connect to Redis and is the cron heartbeat recent?
# Use Ruby since we're in the Rails container
RESULT=$(bundle exec ruby -e "
require 'redis'
require 'time'

begin
  redis = Redis.new(url: '$REDIS_URL')

  # Test ping
  unless redis.ping == 'PONG'
    puts 'PING_FAILED'
    exit 1
  end

  # Test write (catches MISCONF errors)
  test_key = 'sidekiq:health:check'
  redis.setex(test_key, 10, 'ok')

  # Test read
  unless redis.get(test_key) == 'ok'
    puts 'READ_FAILED'
    exit 1
  end

  # Test cron heartbeat (HealthMonitor runs every 5 min, allow 15 min grace period)
  # Skip this check if Sidekiq just started (first 3 minutes)
  sidekiq_start_key = 'sidekiq:health:started_at'
  started_at_str = redis.get(sidekiq_start_key)

  if started_at_str.nil?
    # First run - set the start time and skip heartbeat check
    redis.setex(sidekiq_start_key, 3600, Time.now.iso8601)
    puts 'OK'
    exit 0
  end

  started_at = Time.parse(started_at_str) rescue Time.now
  startup_grace_period = 180 # 3 minutes

  if (Time.now - started_at) > startup_grace_period
    # Past startup grace period - check heartbeat
    heartbeat_key = 'houston:cron:heartbeat'
    heartbeat_str = redis.get(heartbeat_key)

    if heartbeat_str.nil?
      puts 'CRON_NO_HEARTBEAT'
      exit 1
    end

    heartbeat_time = Time.parse(heartbeat_str) rescue nil
    if heartbeat_time.nil?
      puts 'CRON_INVALID_HEARTBEAT'
      exit 1
    end

    # Heartbeat should be within 15 minutes (HealthMonitor runs every 5 min)
    max_age = 900 # 15 minutes
    age = Time.now - heartbeat_time

    if age > max_age
      puts \"CRON_STALE_HEARTBEAT: #{age.to_i}s old\"
      exit 1
    end
  end

  puts 'OK'
rescue Redis::CommandError => e
  # MISCONF or other Redis errors
  puts \"REDIS_ERROR: #{e.message}\"
  exit 1
rescue => e
  puts \"ERROR: #{e.message}\"
  exit 1
end
" 2>&1)

if [ "$RESULT" != "OK" ]; then
    echo "UNHEALTHY: $RESULT"
    exit 1
fi

# All checks passed
exit 0
