# frozen_string_literal: true

module Feeds
  # Centralized guard for feed generation decisions
  # Used by both GenerateFeedInsightsJob and VerifyScheduledJobsJob
  # to ensure consistent behavior and avoid duplication
  #
  # Usage:
  #   guard = Feeds::GenerationGuard.new(user)
  #   result = guard.can_generate?(period)
  #   if result.allowed?
  #     # proceed with generation
  #   else
  #     Rails.logger.info(result.reason)
  #   end
  class GenerationGuard
    MAX_ATTEMPTS_PER_DAY = 3
    IN_PROGRESS_TIMEOUT = 1.hour

    Result = Struct.new(:allowed, :reason, :should_reschedule, keyword_init: true) do
      def allowed?
        allowed
      end

      def blocked?
        !allowed
      end
    end

    def initialize(user)
      @user = user
      @user_agent = user.user_agent
      @timezone = user.timezone_or_default
      @today_start = Time.current.in_time_zone(@timezone).beginning_of_day
    end

    # Check if feed generation is allowed for this period
    # @param period [String] 'morning', 'afternoon', or 'evening'
    # @param force [Boolean] bypass attempt limit check
    # @param scheduled_time [String, nil] HH:MM time the period was scheduled for (for new-user check)
    # @return [Result] with allowed?, reason, and should_reschedule
    def can_generate?(period, force: false, scheduled_time: nil)
      # Check 1: User has active goals?
      unless has_active_goals?
        return Result.new(
          allowed: false,
          reason: "no active goals",
          should_reschedule: true  # Reschedule in case they add goals
        )
      end

      # Check 2: Insights already exist for this period today?
      if insights_exist?(period)
        return Result.new(
          allowed: false,
          reason: "insights already exist",
          should_reschedule: true
        )
      end

      # Check 3: Generation already in progress?
      if generation_in_progress?
        return Result.new(
          allowed: false,
          reason: "generation in progress",
          should_reschedule: true
        )
      end

      # Check 4: Too many attempts today? (skipped if force=true)
      unless force
        attempts = attempts_today(period)
        if attempts >= MAX_ATTEMPTS_PER_DAY
          return Result.new(
            allowed: false,
            reason: "max attempts (#{MAX_ATTEMPTS_PER_DAY}) reached",
            should_reschedule: true
          )
        end
      end

      # Check 5: Skip retroactive generation for new users.
      # If user's first goal was created AFTER this period's time today, don't generate.
      # Prevents a user who creates their first goal at 2pm from getting "morning" insights.
      if new_user_retroactive?(scheduled_time)
        return Result.new(
          allowed: false,
          reason: "new user - first goal created after period time",
          should_reschedule: true
        )
      end

      Result.new(allowed: true, reason: nil, should_reschedule: true)
    end

    # Check if insights exist for this period today
    def insights_exist?(period)
      FeedInsight.where(user: @user, time_period: period)
                 .where('created_at >= ?', @today_start)
                 .exists?
    end

    # Check if feed generation is currently in progress.
    #
    # Two-phase detection covers the orchestrator startup window:
    #
    # Phase 1 (~0-30s): GenerateFeedInsightsJob sets feed_period + starts orchestrator.
    #   The orchestrator is running but no AgentTask exists yet.
    #   Detected by: orchestrator_running + feed_period present.
    #
    # Phase 2 (30s+): Orchestrator creates AgentTask via create_task tool.
    #   The task carries origin_type='feed_generation' in context_data
    #   (mapped from parent's 'type' to avoid triggering child's execution mode dispatch).
    #   Detected by: active AgentTask with origin_type='feed_generation'.
    #
    # Both checks prevent duplicate feed generation during the same run.
    def generation_in_progress?
      return false unless @user_agent

      orchestrator_running_for_feed? || active_feed_task_exists?
    end

    # Get number of generation attempts within the last 24 hours for this period
    def attempts_today(period)
      return 0 unless @user_agent
      @user_agent.feed_attempt_count(period)
    end

    # Record a generation attempt
    def record_attempt!(period)
      return unless @user_agent
      @user_agent.record_feed_attempt!(period)
    rescue StandardError => e
      Rails.logger.error("[Feeds::GenerationGuard] Failed to record attempt: #{e.message}")
    end

    # Check if user has active goals
    def has_active_goals?
      @user.goals.where.not(status: :archived).exists?
    end

    # Get count of active goals (for logging)
    def active_goals_count
      @user.goals.where.not(status: :archived).count
    end

    # Timezone accessor for logging
    attr_reader :timezone, :today_start

    private

    # Phase 1: Orchestrator is running and was started for feed generation
    # (covers the window before AgentTask is created by the create_task tool)
    def orchestrator_running_for_feed?
      return false unless @user_agent.agent_running?
      return false unless @user_agent.feed_period.present?

      started_at = @user_agent.orchestrator_started_at
      return false unless started_at.present?

      elapsed = Time.current - Time.parse(started_at.to_s)
      elapsed < IN_PROGRESS_TIMEOUT
    end

    # Phase 2: Active AgentTask created by a feed generation run.
    # Feed tasks carry origin_type='feed_generation' (mapped from parent's 'type' key
    # to avoid triggering the orchestrator's execution mode dispatch).
    def active_feed_task_exists?
      AgentTask.where(taskable: @user_agent, status: :active)
               .where('created_at >= ?', IN_PROGRESS_TIMEOUT.ago)
               .where("context_data->>'origin_type' = ?", 'feed_generation')
               .exists?
    end

    # Check if this is a new user who created their first goal after this period's
    # scheduled time today. Used to avoid retroactively generating e.g. "morning"
    # insights at 3pm just because the user signed up and added a goal after lunch.
    def new_user_retroactive?(scheduled_time)
      return false unless scheduled_time.present?

      first_goal_created_at = @user.goals.minimum(:created_at)
      return false unless first_goal_created_at

      hour, minute = scheduled_time.split(':').map(&:to_i)
      period_time = @today_start.change(hour: hour, min: minute)

      first_goal_created_at > period_time
    end
  end
end
