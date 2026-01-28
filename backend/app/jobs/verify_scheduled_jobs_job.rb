# frozen_string_literal: true

# Hourly safety net that verifies scheduled jobs exist and triggers missed generations
#
# Two responsibilities:
# 1. Repair missing Sidekiq jobs (lost to Redis issues, restarts, etc.)
# 2. Trigger missed feed generations (job ran but orchestrator failed)
#
# Uses Feeds::GenerationGuard for consistent validation with GenerateFeedInsightsJob
#
# Runs hourly via Sidekiq Cron (see config/initializers/sidekiq_cron.rb)
class VerifyScheduledJobsJob
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  # How long after scheduled time before we consider it "missed"
  # Should be longer than InsightScheduler::RANDOMIZATION_WINDOW (15 min)
  GRACE_PERIOD = 30.minutes

  def perform
    require 'sidekiq/api'

    @scheduled_set = Sidekiq::ScheduledSet.new
    @stats = Hash.new(0)

    UserAgent.includes(:user).find_each do |user_agent|
      process_user(user_agent)
    end

    Goal.find_each do |goal|
      verify_goal_checkins(goal)
    end

    log_summary
  end

  private

  def process_user(user_agent)
    schedule = user_agent.feed_schedule
    return unless schedule && schedule['enabled'] != false

    # Check for missed feeds and trigger if needed
    check_missed_feeds(user_agent, schedule)

    # Detect periods where attempts were made but no insights produced
    check_empty_completions(user_agent, schedule)

    # Verify Sidekiq jobs exist
    verify_sidekiq_jobs(user_agent, schedule)
  end

  # Trigger generation for any periods where time passed but no insights exist
  def check_missed_feeds(user_agent, schedule)
    user = user_agent.user
    guard = Feeds::GenerationGuard.new(user)

    # Quick check: skip users with no active goals
    unless guard.has_active_goals?
      @stats[:feeds_skipped_no_goals] += 1
      return
    end

    now = Time.current.in_time_zone(guard.timezone)
    today_start = guard.today_start
    periods = schedule['periods'] || {}

    periods.each do |period, config|
      next unless period_is_missed?(config, now, today_start)

      # Guard handles all checks: existing insights, in-progress, max attempts,
      # and new-user retroactive skip (via scheduled_time parameter)
      result = guard.can_generate?(period, scheduled_time: config['time'])

      if result.allowed?
        attempts = guard.attempts_today(period)
        Rails.logger.warn("[VerifyScheduledJobs] User #{user.id}: Triggering missed #{period} feed (attempt #{attempts + 1})")
        GenerateFeedInsightsJob.perform_async(user.id, period)
        @stats[:feeds_triggered] += 1
      else
        track_skip_reason(result.reason)
      end
    end
  end

  # Detect periods where generation was attempted but produced no insights.
  # This catches silent failures like LLM refusals or tool errors where
  # the task completes but no FeedInsight records are created.
  def check_empty_completions(user_agent, schedule)
    user = user_agent.user
    guard = Feeds::GenerationGuard.new(user)
    now = Time.current.in_time_zone(guard.timezone)
    today_start = guard.today_start
    periods = schedule['periods'] || {}

    periods.each do |period, config|
      next unless period_is_missed?(config, now, today_start)

      attempts = guard.attempts_today(period)
      next unless attempts > 0
      next if guard.insights_exist?(period)
      next if guard.generation_in_progress?

      Rails.logger.warn(
        "[VerifyScheduledJobs] User #{user.id}: #{period} had #{attempts} attempt(s) but produced 0 insights"
      )
      @stats[:feeds_empty_completion] += 1
    end
  end

  # Check if a period's time has passed (with grace period)
  def period_is_missed?(config, now, today_start)
    return false unless config['enabled'] != false
    return false unless config['time'].present?

    hour, minute = config['time'].split(':').map(&:to_i)
    scheduled_time = today_start.change(hour: hour, min: minute)

    now > scheduled_time + GRACE_PERIOD
  end

  def track_skip_reason(reason)
    case reason
    when /insights already exist/
      # Expected - feed was generated successfully
    when /in progress/
      @stats[:feeds_skipped_in_progress] += 1
    when /max attempts/
      @stats[:feeds_skipped_max_attempts] += 1
    when /no active goals/
      @stats[:feeds_skipped_no_goals] += 1
    when /new user/
      @stats[:feeds_skipped_new_user] += 1
    end
  end

  # Ensure Sidekiq jobs exist for future scheduled periods
  def verify_sidekiq_jobs(user_agent, schedule)
    return unless schedule

    result = Feeds::ScheduleVerifier.new(user_agent)
               .verify_and_repair!(scheduled_set: @scheduled_set)

    case result
    when :repaired then @stats[:feed_schedules_repaired] += 1
    when :healthy  then @stats[:feed_schedules_healthy] += 1
    end
  end

  def verify_goal_checkins(goal)
    # Check scheduled_check_in (recurring check-ins)
    if (scheduled = goal.scheduled_check_in)
      verify_checkin(goal, 'scheduled', scheduled)
    end

    # Check next_follow_up (one-time follow-ups)
    if (follow_up = goal.next_follow_up)
      verify_checkin(goal, 'follow_up', follow_up)
    end
  end

  def verify_checkin(goal, slot, check_in)
    job_id = check_in['job_id']
    scheduled_for = Time.parse(check_in['scheduled_for']) rescue nil
    return unless job_id && scheduled_for

    # If past, clear it from state (it should have fired)
    if scheduled_for < Time.current
      Rails.logger.warn("[VerifyScheduledJobs] Goal #{goal.id}: Clearing past #{slot} check-in (was scheduled for #{scheduled_for})")
      clear_past_checkin(goal, slot)
      @stats[:checkins_cleared_past] += 1
      return
    end

    if @scheduled_set.find_job(job_id).nil?
      Rails.logger.warn("[VerifyScheduledJobs] Goal #{goal.id}: Repairing missing #{slot} check-in")
      repair_checkin(goal, slot, check_in, scheduled_for)
      @stats[:checkins_repaired] += 1
    else
      @stats[:checkins_healthy] += 1
    end
  end

  def clear_past_checkin(goal, slot)
    if slot == 'scheduled'
      goal.clear_scheduled_check_in!
    else
      goal.clear_next_follow_up!
    end
  end

  def repair_checkin(goal, slot, check_in, scheduled_for)
    new_job_id = Jobs::Scheduler.schedule_check_in(
      goal,
      slot,
      scheduled_for,
      check_in['intent']
    )

    goal.update_runtime_state! do |state|
      state_key = slot == 'scheduled' ? 'scheduled_check_in' : 'next_follow_up'
      state[state_key]['job_id'] = new_job_id
    end
  end

  def log_summary
    triggered = @stats[:feeds_triggered]
    repaired = @stats[:feed_schedules_repaired] + @stats[:checkins_repaired]
    empty = @stats[:feeds_empty_completion]

    if triggered.positive? || repaired.positive? || empty.positive?
      Rails.logger.info(
        "[VerifyScheduledJobs] Actions: #{triggered} feeds triggered, " \
        "#{@stats[:feed_schedules_repaired]} schedules repaired, " \
        "#{@stats[:checkins_repaired]} check-ins repaired" \
        "#{empty.positive? ? ", #{empty} empty completions detected" : ''}"
      )
    end

    skipped = @stats[:feeds_skipped_in_progress].to_i + @stats[:feeds_skipped_max_attempts].to_i + @stats[:feeds_skipped_new_user].to_i
    if skipped.positive?
      Rails.logger.debug(
        "[VerifyScheduledJobs] Skipped: #{@stats[:feeds_skipped_in_progress]} in progress, " \
        "#{@stats[:feeds_skipped_max_attempts]} max attempts, " \
        "#{@stats[:feeds_skipped_new_user]} new users"
      )
    end
  end
end
