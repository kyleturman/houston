# frozen_string_literal: true

module Jobs
  # Verifies and repairs scheduled jobs on server/worker startup
  #
  # Called from:
  # - Rails web server boot (config/initializers/scheduled_jobs.rb)
  # - Sidekiq worker startup (config/initializers/sidekiq_startup.rb)
  #
  # This ensures jobs are restored after any restart, not just web server restarts.
  class StartupVerifier
    HEARTBEAT_KEY = 'houston:cron:heartbeat'
    HEARTBEAT_TTL = 15.minutes.to_i

    def self.verify!
      new.verify!
    end

    def self.write_heartbeat!
      Sidekiq.redis do |redis|
        redis.set(HEARTBEAT_KEY, Time.current.iso8601, ex: HEARTBEAT_TTL)
      end
    end

    def self.heartbeat_healthy?
      last_heartbeat = Sidekiq.redis { |redis| redis.get(HEARTBEAT_KEY) }
      return false unless last_heartbeat

      # Heartbeat should be within 10 minutes (HealthMonitor runs every 5 min)
      Time.parse(last_heartbeat) > 10.minutes.ago
    rescue => e
      Rails.logger.error("[StartupVerifier] Heartbeat check failed: #{e.message}")
      false
    end

    def verify!
      Rails.logger.info('[StartupVerifier] Verifying all scheduled jobs and execution locks...')

      require 'sidekiq/api'

      @scheduled_set = Sidekiq::ScheduledSet.new
      @feed_fixed = 0
      @feed_healthy = 0
      @checkin_fixed = 0
      @checkin_healthy = 0
      @locks_cleared = 0

      # Clear stale execution locks first (before verifying other jobs)
      clear_orphaned_execution_locks!

      verify_feed_schedules
      verify_check_ins

      Rails.logger.info(
        "[StartupVerifier] ✓ Verification complete: " \
        "feeds (#{@feed_healthy} healthy, #{@feed_fixed} repaired), " \
        "check-ins (#{@checkin_healthy} healthy, #{@checkin_fixed} repaired), " \
        "execution locks cleared: #{@locks_cleared}"
      )

      { feeds: { healthy: @feed_healthy, repaired: @feed_fixed },
        checkins: { healthy: @checkin_healthy, repaired: @checkin_fixed },
        locks_cleared: @locks_cleared }
    rescue => e
      Rails.logger.error("[StartupVerifier] Verification failed: #{e.message}")
      nil
    end

    private

    # Clear execution locks for orchestrator jobs that no longer exist
    # This handles the case where Sidekiq restarted mid-execution
    def clear_orphaned_execution_locks!
      # Get all running Sidekiq jobs to check against
      running_jobs = Sidekiq::Workers.new.to_a.map { |_, _, work| work['payload']['jid'] }.compact
      queued_jobs = Sidekiq::Queue.new.map(&:jid)
      all_active_jobs = Set.new(running_jobs + queued_jobs)

      # Check all agentable types
      [Goal, AgentTask, UserAgent].each do |klass|
        check_locks_for_model(klass, all_active_jobs)
      end
    end

    def check_locks_for_model(klass, all_active_jobs)
      # Find records with orchestrator_running = true
      locked_records = klass.where("runtime_state->>'orchestrator_running' = 'true'")

      locked_records.find_each do |record|
        job_id = record.orchestrator_job_id
        started_at = record.orchestrator_started_at

        # If no job_id stored, the lock is definitely orphaned
        # If job_id exists but job is not in Sidekiq, the lock is orphaned
        # Also clear if the lock is very old (>30 minutes) as a safety net
        is_orphaned = job_id.nil? || !all_active_jobs.include?(job_id)
        is_stale = started_at && Time.parse(started_at.to_s) < 30.minutes.ago

        if is_orphaned || is_stale
          reason = if job_id.nil?
                     'no job_id stored'
                   elsif is_stale
                     "stale (started #{started_at})"
                   else
                     "job #{job_id} not found in Sidekiq"
                   end

          Rails.logger.warn(
            "[StartupVerifier] Clearing orphaned execution lock for #{klass.name}##{record.id}: #{reason}"
          )

          # Also validate and repair LLM history since the orchestrator may have crashed mid-tool
          if record.respond_to?(:llm_history) && record.llm_history.present?
            validator = Agents::HistoryValidator.new(record)
            validation_result = validator.validate_and_repair!
            if validation_result.repaired?
              Rails.logger.warn(
                "[StartupVerifier] Repaired LLM history for #{klass.name}##{record.id}: #{validation_result.repairs.join(', ')}"
              )
            end
          end

          record.release_execution_lock!
          @locks_cleared += 1
        end
      end
    rescue => e
      Rails.logger.error("[StartupVerifier] Error checking locks for #{klass.name}: #{e.message}")
    end

    def verify_feed_schedules
      UserAgent.find_each do |user_agent|
        result = Feeds::ScheduleVerifier.new(user_agent)
                   .verify_and_repair!(scheduled_set: @scheduled_set)

        case result
        when :repaired then @feed_fixed += 1
        when :healthy  then @feed_healthy += 1
        end
      end
    end

    def verify_check_ins
      Goal.find_each do |goal|
        verify_scheduled_check_in(goal)
        verify_follow_up_check_in(goal)
      end
    end

    def verify_scheduled_check_in(goal)
      scheduled = goal.scheduled_check_in

      if scheduled
        job_id = scheduled['job_id']
        scheduled_for = Time.parse(scheduled['scheduled_for']) rescue nil

        if job_id && scheduled_for
          is_past = scheduled_for < Time.current
          job_missing = !@scheduled_set.find_job(job_id)

          if is_past || job_missing
            if goal.has_check_in_schedule?
              Rails.logger.warn(
                "[StartupVerifier] Goal #{goal.id}: #{is_past ? 'Missed' : 'Missing'} scheduled check-in, rescheduling"
              )
              begin
                calculator = Goals::ScheduleCalculator.new(goal)
                calculator.schedule_next_check_in!
                @checkin_fixed += 1
              rescue => e
                Rails.logger.error("[StartupVerifier] Goal #{goal.id}: Failed to reschedule: #{e.message}")
              end
            else
              # No schedule configured, clear the stale entry
              goal.clear_scheduled_check_in!
            end
          else
            @checkin_healthy += 1
          end
        end
      elsif goal.has_check_in_schedule?
        # Has schedule but no scheduled_check_in in runtime_state
        Rails.logger.warn("[StartupVerifier] Goal #{goal.id}: Has schedule but no scheduled_check_in, scheduling")
        begin
          calculator = Goals::ScheduleCalculator.new(goal)
          calculator.schedule_next_check_in!
          @checkin_fixed += 1
        rescue => e
          Rails.logger.error("[StartupVerifier] Goal #{goal.id}: Failed to schedule: #{e.message}")
        end
      end
    end

    def verify_follow_up_check_in(goal)
      follow_up = goal.next_follow_up
      return unless follow_up

      job_id = follow_up['job_id']
      scheduled_for = Time.parse(follow_up['scheduled_for']) rescue nil
      return unless job_id && scheduled_for

      if scheduled_for < Time.current
        # Past follow-up: clear it
        Rails.logger.warn("[StartupVerifier] Goal #{goal.id}: Clearing past follow-up check-in")
        goal.clear_next_follow_up!
        goal.clear_original_follow_up!
      elsif !@scheduled_set.find_job(job_id)
        # Future but missing job: reschedule
        Rails.logger.warn("[StartupVerifier] Goal #{goal.id}: Repairing missing follow_up check-in")

        new_job_id = Jobs::Scheduler.schedule_check_in(
          goal,
          'follow_up',
          scheduled_for,
          follow_up['intent']
        )

        goal.update_runtime_state! do |state|
          state['next_follow_up']['job_id'] = new_job_id
        end

        @checkin_fixed += 1
      else
        @checkin_healthy += 1
      end
    end

  end
end
