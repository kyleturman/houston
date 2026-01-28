# frozen_string_literal: true

module Feeds
  # Verifies and repairs feed insight scheduling for a single UserAgent.
  #
  # Checks whether the Sidekiq jobs referenced in the user's feed_schedule
  # still exist in the Sidekiq scheduled set. If any are missing (due to Redis
  # flush, restart, etc.), cancels all and reschedules via InsightScheduler.
  #
  # Used by:
  # - Jobs::StartupVerifier (on server/worker boot)
  # - VerifyScheduledJobsJob (hourly safety net)
  #
  # Usage:
  #   verifier = Feeds::ScheduleVerifier.new(user_agent)
  #   result = verifier.verify_and_repair!(scheduled_set: Sidekiq::ScheduledSet.new)
  #   # => :healthy, :repaired, or :skipped
  class ScheduleVerifier
    def initialize(user_agent)
      @user_agent = user_agent
      @scheduler = InsightScheduler.new(user_agent)
    end

    # Check if all scheduled feed jobs exist in Sidekiq.
    # @param scheduled_set [Sidekiq::ScheduledSet] reuse across batch for performance
    # @return [Symbol] :healthy, :repaired, or :skipped
    def verify_and_repair!(scheduled_set:)
      schedule = @user_agent.feed_schedule
      return :skipped unless schedule && schedule['enabled'] != false

      jobs = schedule['jobs'] || {}
      return :skipped if jobs.empty?

      missing_jobs = find_missing_jobs(jobs, scheduled_set)

      if missing_jobs.any?
        repair!(missing_jobs.count, jobs.count)
        :repaired
      else
        :healthy
      end
    end

    private

    def find_missing_jobs(jobs, scheduled_set)
      jobs.select do |_period, job_data|
        job_id = job_data['job_id']
        job_id && scheduled_set.find_job(job_id).nil?
      end
    end

    def repair!(missing_count, total_count)
      Rails.logger.warn(
        "[Feeds::ScheduleVerifier] User #{@user_agent.user_id}: " \
        "Repairing #{missing_count}/#{total_count} missing feed jobs"
      )

      @scheduler.cancel_all!
      @scheduler.schedule_all!
    end
  end
end
