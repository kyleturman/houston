# frozen_string_literal: true

# Sidekiq startup hooks for job verification and health monitoring
#
# This ensures scheduled jobs are verified when Sidekiq starts,
# not just when the web server starts. This catches cases where:
# - Only Sidekiq was restarted (not the web server)
# - Redis was cleared/restarted
# - Jobs were lost due to crashes

if defined?(Sidekiq)
  Sidekiq.configure_server do |config|
    config.on(:startup) do
      # Run job verification in a background thread to not block Sidekiq startup
      Thread.new do
        # Wait for Sidekiq to fully initialize and cron jobs to register
        sleep 2

        begin
          Jobs::StartupVerifier.verify!
        rescue => e
          Rails.logger.error("[Sidekiq Startup] Job verification failed: #{e.message}")
        end
      end
    end
  end
end
