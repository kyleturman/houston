# frozen_string_literal: true

# Background job to clean up old feed insights
# Runs daily to remove insights older than 7 days
class CleanupOldFeedInsightsJob
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  def perform
    deleted_count = FeedInsight.cleanup_old_insights
    Rails.logger.info "[CleanupOldFeedInsightsJob] Cleaned up #{deleted_count} old insights (>7 days)"
  end
end
