# frozen_string_literal: true

# Scheduled job verification on Rails web server startup
#
# Ensures all user-scheduled jobs (feed schedules, check-ins) are restored after server restarts.
# Uses the shared Jobs::StartupVerifier service (also called from Sidekiq startup).
#
# This runs automatically when Rails boots, but you can also run it manually:
#   docker-compose exec backend bundle exec rails jobs:verify

Rails.application.config.after_initialize do
  # Only run if:
  # 1. We're in a web server process (not console, rake, etc.)
  # 2. Database is available
  next if Rails.env.test?
  next if defined?(Rails::Console)
  next unless ActiveRecord::Base.connection.table_exists?('user_agents')

  # Delay check slightly to let Sidekiq start
  Thread.new do
    sleep 2

    begin
      Jobs::StartupVerifier.verify!
    rescue => e
      Rails.logger.error("[ScheduledJobs] Verification failed: #{e.message}")
    end
  end
end
