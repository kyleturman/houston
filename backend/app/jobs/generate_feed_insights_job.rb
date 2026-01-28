# frozen_string_literal: true

# Scheduled job that triggers UserAgent to generate feed insights
# Runs 3x/day per user (morning, afternoon, evening) and reschedules itself
#
# Deduplication is handled by Feeds::GenerationGuard which checks:
# - Do insights already exist for this period today?
# - Is generation currently in progress?
# - Have we exceeded max attempts for this period?
#
# See also:
# - Feeds::GenerationGuard - shared validation logic
# - Feeds::InsightScheduler - manages scheduling
# - VerifyScheduledJobsJob - hourly safety net for missed generations
class GenerateFeedInsightsJob
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  # @param user_id [Integer] User ID
  # @param period [String] 'morning', 'afternoon', or 'evening'
  # @param options [Hash] Optional: { 'force' => true } to bypass attempt limit
  def perform(user_id, period, options = {})
    user = User.find_by(id: user_id)
    return unless user&.user_agent

    user_agent = user.user_agent
    scheduler = Feeds::InsightScheduler.new(user_agent)
    force = options['force'] || options[:force]

    # Skip if this period is disabled in user settings
    unless scheduler.period_enabled?(period)
      log(:info, user_id, period, "period is disabled")
      return
    end

    # Use guard to check if generation is allowed
    guard = Feeds::GenerationGuard.new(user)
    result = guard.can_generate?(period, force: force)

    unless result.allowed?
      log(:info, user_id, period, result.reason)
      reschedule_if_needed(scheduler, user_agent, period, result)
      return
    end

    # All checks passed - proceed with generation
    log(:info, user_id, period, "generating (#{guard.active_goals_count} active goals)")

    # Record attempt before triggering (for retry limiting)
    guard.record_attempt!(period)

    # Trigger the actual generation via UserAgent orchestrator
    trigger_insight_generation(user, period)

    # Reschedule for tomorrow (self-perpetuating)
    reschedule_next(scheduler, user_agent, period)
  end

  private

  def trigger_insight_generation(user, period)
    user_agent = user.user_agent

    # Store period in runtime_state so the generate_feed_insights tool can access it
    user_agent.set_feed_period!(period)

    Agents::Orchestrator.perform_async(
      'UserAgent',
      user_agent.id,
      {
        'type' => 'feed_generation',
        'time_of_day' => period,
        'scheduled' => true
      }
    )
  end

  def reschedule_if_needed(scheduler, user_agent, period, result)
    return unless result.should_reschedule
    reschedule_next(scheduler, user_agent, period)
  end

  def reschedule_next(scheduler, user_agent, period)
    # Skip rescheduling in test environment to avoid infinite loops
    return if Rails.env.test?

    if scheduler.enabled? && scheduler.period_enabled?(period)
      scheduler.schedule_next(period)
    else
      log(:info, user_agent.user_id, period, "scheduling disabled, not rescheduling")
    end
  rescue StandardError => e
    Rails.logger.error("[FeedInsights] Failed to reschedule #{period} for user #{user_agent.user_id}: #{e.message}")
  end

  def log(level, user_id, period, message)
    Rails.logger.send(level, "[FeedInsights] #{period} for user #{user_id}: #{message}")
  end
end
