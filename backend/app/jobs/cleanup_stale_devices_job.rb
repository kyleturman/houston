# frozen_string_literal: true

# CleanupStaleDevicesJob
#
# Removes devices that haven't been used in over 30 days to keep database clean
# and improve security by revoking old device tokens.
#
# Runs daily at 4 AM via Sidekiq Cron
class CleanupStaleDevicesJob
  include Sidekiq::Job

  STALE_THRESHOLD_DAYS = 30

  def perform
    cutoff_date = STALE_THRESHOLD_DAYS.days.ago

    # Find devices that:
    # 1. Haven't been used in 30+ days (last_used_at < cutoff)
    # 2. Were created 30+ days ago but never used (last_used_at IS NULL AND created_at < cutoff)
    stale_devices = Device.where('last_used_at < ? OR (last_used_at IS NULL AND created_at < ?)', cutoff_date, cutoff_date)
    count = stale_devices.count

    if count > 0
      Rails.logger.info("[CleanupStaleDevicesJob] Found #{count} stale devices (not used in #{STALE_THRESHOLD_DAYS}+ days)")
      stale_devices.destroy_all
      Rails.logger.info("[CleanupStaleDevicesJob] Successfully cleaned up #{count} stale devices")
    else
      Rails.logger.info("[CleanupStaleDevicesJob] No stale devices found")
    end
  end
end
