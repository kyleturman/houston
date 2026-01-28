# frozen_string_literal: true

# Schedule health monitoring and cleanup jobs
if defined?(Sidekiq::Cron::Job)
  Sidekiq::Cron::Job.load_from_hash({
    # Run agent health monitor every 5 minutes
    'agent_health_monitor' => {
      'cron' => '*/5 * * * *',  # Every 5 minutes
      'class' => 'Agents::HealthMonitor'
    },
    # Verify scheduled jobs exist and repair missing ones
    # Catches issues from Redis failures, missed reschedules, etc.
    'verify_scheduled_jobs' => {
      'cron' => '0 * * * *',  # Every hour
      'class' => 'VerifyScheduledJobsJob'
    },
    # Cleanup old feed insights daily at 3 AM
    'cleanup_old_feed_insights' => {
      'cron' => '0 3 * * *',  # Daily at 3 AM
      'class' => 'CleanupOldFeedInsightsJob'
    },
    # Cleanup stale devices daily at 4 AM
    'cleanup_stale_devices' => {
      'cron' => '0 4 * * *',  # Daily at 4 AM
      'class' => 'CleanupStaleDevicesJob'
    }
  })
end
