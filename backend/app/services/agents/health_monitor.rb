# frozen_string_literal: true

module Agents
  # Monitors agent health and fixes common issues
  class HealthMonitor
    include Sidekiq::Worker
    sidekiq_options queue: :default, retry: false

    # Run health checks every 5 minutes
    def perform
      # Write heartbeat first - this lets the health check detect if cron jobs are running
      Jobs::StartupVerifier.write_heartbeat!

      Rails.logger.info("[HealthMonitor] Starting agent health check")

      check_stuck_orchestrators
      check_stale_agents
      check_excessive_history
      check_inconsistent_states
      check_paused_task_retry
      check_paused_task_expiry
      cleanup_completed_agents
      ensure_goal_heartbeats

      Rails.logger.info("[HealthMonitor] Health check completed")
    end

    private

    # Find orchestrators stuck with running flag for too long and release their lock
    def check_stuck_orchestrators
      threshold = Constants::STUCK_ORCHESTRATOR_THRESHOLD.ago

      # Check all agentable types: Goals, AgentTasks, UserAgent
      [Goal, AgentTask, UserAgent].each do |klass|
        stuck = klass.where("runtime_state->>'orchestrator_running' = 'true'")
                     .where("(runtime_state->>'orchestrator_started_at')::timestamp < ?", threshold)

        stuck.each do |agentable|
          started_at = agentable.orchestrator_started_at
          Rails.logger.warn("[HealthMonitor] Found stuck orchestrator on #{klass.name}##{agentable.id} (started: #{started_at}) - cancelling job and releasing lock")

          begin
            # Cancel the actual Sidekiq job first (prevents zombie processes)
            cancel_orchestrator_job(agentable)

            # Release the execution lock
            agentable.release_execution_lock!

            # For tasks, mark as completed to prevent retry loops
            if agentable.is_a?(AgentTask)
              agentable.update!(
                status: :completed,
                result_summary: "Task completed by health monitor - orchestrator was stuck"
              )
            end

            Rails.logger.info("[HealthMonitor] Released stuck lock for #{klass.name}##{agentable.id}")
          rescue => e
            Rails.logger.error("[HealthMonitor] Failed to release stuck lock for #{klass.name}##{agentable.id}: #{e.message}")
          end
        end
      end
    end

    # Find tasks that haven't been updated in a while and complete them
    def check_stale_agents
      stale_task_threshold = Rails.env.production? ?
        Constants::STALE_TASK_THRESHOLD_PRODUCTION.ago :
        Constants::STALE_TASK_THRESHOLD_DEV.ago

      stale_tasks = AgentTask.where(status: :active)
        .where("updated_at < ?", stale_task_threshold)

      stale_tasks.each do |task|
        Rails.logger.warn("[HealthMonitor] Found stale task #{task.id} - completing")

        task.update!(
          status: :completed,
          result_summary: "Task completed by health monitor - task was stale"
        )
      end

      # Also check for stale goals (goals should persist longer)
      stale_goal_threshold = Rails.env.production? ?
        Constants::STALE_GOAL_THRESHOLD_PRODUCTION.ago :
        Constants::STALE_GOAL_THRESHOLD_DEV.ago

      stale_goals = Goal.where(status: :working)
        .where("updated_at < ?", stale_goal_threshold)

      stale_goals.each do |goal|
        Rails.logger.warn("[HealthMonitor] Found stale goal #{goal.id} - setting to waiting")
        goal.update!(status: :waiting)
      end
    end

    # Find tasks with excessive LLM history (safety net - CoreLoop should prevent this)
    # Note: CoreLoop stops tasks at MAX_TASK_HISTORY_LENGTH=20, so this is a failsafe
    def check_excessive_history
      AgentTask.where(status: :active).find_each do |task|
        history = task.get_llm_history
        history_count = history.length

        # Failsafe: Stop tasks with excessive history (CoreLoop should prevent this at 20)
        if history_count > Constants::HEALTH_EXCESSIVE_HISTORY_LIMIT
          Rails.logger.error("[HealthMonitor] Task #{task.id} exceeded history limit (#{history_count}) - this should not happen!")

          task.update!(
            status: :completed,
            result_summary: "Task stopped by health monitor - excessive LLM history (#{history_count} entries)"
          )
          next
        end

        # Warning for high history count (approaching CoreLoop's limit)
        if history_count > Constants::HEALTH_HIGH_HISTORY_WARNING
          Rails.logger.warn("[HealthMonitor] Task #{task.id} has high history count: #{history_count}")
        end
      end
    end

    # Fix inconsistent states - placeholder for future consistency checks.
    # runtime_state no longer stores a 'status' key, so previous checks are removed.
    def check_inconsistent_states
      # No-op: agent status is tracked via model columns, not runtime_state
    end

    # Retry paused tasks that are ready for retry
    def check_paused_task_retry
      ready_tasks = AgentTask.where(status: :paused)
        .where('next_retry_at IS NULL OR next_retry_at <= ?', Time.current)
      
      ready_tasks.each do |task|
        next unless task.retryable?
        
        Rails.logger.info("[HealthMonitor] Retrying paused task #{task.id} (attempt #{task.retry_count + 1})")
        
        # Restart the task (it's now directly agentable)
        begin
          # Update task to active status and start orchestrator
          task.update!(status: :active)
          task.start_orchestrator!
          
          Rails.logger.info("[HealthMonitor] Started retry for task #{task.id}")
          
        rescue => e
          Rails.logger.error("[HealthMonitor] Failed to retry task #{task.id}: #{e.message}")

          # If we can't create the retry, pause it again with longer delay
          task.pause_with_error!(
            :retry_failed,
            "Failed to create retry: #{e.message}",
            Constants::HEALTH_RETRY_FAILED_DELAY.to_i
          )
        end
      end
    end

    # Convert old paused tasks to cancelled after 24 hours
    def check_paused_task_expiry
      expiry_threshold = Constants::PAUSED_TASK_EXPIRY_THRESHOLD.ago
      expired_tasks = AgentTask.where(status: :paused)
        .where("updated_at < ?", expiry_threshold)
      
      expired_tasks.each do |task|
        Rails.logger.info("[HealthMonitor] Converting expired paused task #{task.id} to cancelled")
        
        reason = case task.error_type
        when 'rate_limit'
          'Task paused due to API rate limits and expired after 24 hours'
        when 'network'
          'Task paused due to network issues and expired after 24 hours'
        when 'mcp_error'
          'Task paused due to external tool errors and expired after 24 hours'
        else
          'Task paused due to temporary error and expired after 24 hours'
        end
        
        task.cancel_with_reason!(reason)
      end
    end

    # Clean up old completed tasks to prevent database bloat
    def cleanup_completed_agents
      old_threshold = Constants::COMPLETED_TASK_CLEANUP_THRESHOLD.ago
      old_tasks = AgentTask.where(status: [:completed, :cancelled])
        .where("updated_at < ?", old_threshold)

      if old_tasks.count > 0
        Rails.logger.info("[HealthMonitor] Cleaning up #{old_tasks.count} old completed tasks")
        old_tasks.delete_all
      end
    end

    # Ensure all active goals have at least one check-in scheduled
    # Goals can have:
    #   - check_in_schedule: Recurring check-ins (daily, weekly, etc.) stored in scheduled_check_in
    #   - next_follow_up: One-time contextual follow-ups
    #
    # This fallback ensures:
    #   1. Goals with a schedule have their next occurrence scheduled
    #   2. Goals without a schedule have a follow-up scheduled
    def ensure_goal_heartbeats
      Goal.where(status: [:working, :waiting]).find_each do |goal|
        # Check if goal has any check-in scheduled
        has_scheduled = goal.scheduled_check_in.present?
        has_follow_up = goal.next_follow_up.present?

        # If goal has a schedule but no scheduled_check_in, schedule the next occurrence
        if goal.has_check_in_schedule? && !has_scheduled
          Rails.logger.info("[HealthMonitor] Scheduling next occurrence for Goal##{goal.id} (has schedule)")
          calculator = Goals::ScheduleCalculator.new(goal)
          calculator.schedule_next_check_in!
          publish_goal_updated(goal)
          next
        end

        # If goal has either a scheduled check-in or a follow-up, it's covered
        next if has_scheduled || has_follow_up

        # No check-in scheduled - create a fallback follow-up based on activity
        activity = Goals::ActivityCalculator.new(goal).calculate
        base_delay = base_delay_for_activity(activity[:level])
        scheduled_time = base_delay.hours.from_now

        Rails.logger.info("[HealthMonitor] Scheduling fallback follow-up for Goal##{goal.id} (activity: #{activity[:level]}, delay: #{base_delay}h)")

        # Schedule follow-up check-in
        job_id = AgentCheckInJob.perform_at(
          scheduled_time,
          'Goal',
          goal.id,
          'follow_up',
          {
            'intent' => 'Review goal and recent activity',
            'created_at' => Time.current.iso8601
          }
        )

        # Store as next_follow_up
        goal.set_next_follow_up!({
          'job_id' => job_id,
          'scheduled_for' => scheduled_time.iso8601,
          'intent' => 'Review goal and recent activity',
          'created_at' => Time.current.iso8601
        })

        publish_goal_updated(goal)
      rescue => e
        Rails.logger.error("[HealthMonitor] Failed to ensure check-in for Goal##{goal.id}: #{e.message}")
      end
    end

    # Base delay hours by activity level (no decay - simpler model)
    def base_delay_for_activity(level)
      case level
      when :high then Constants::HEARTBEAT_HIGH_ACTIVITY_HOURS
      when :moderate then Constants::HEARTBEAT_MODERATE_ACTIVITY_HOURS
      else Constants::HEARTBEAT_LOW_ACTIVITY_HOURS
      end
    end

    # Cancel the actual Sidekiq job to prevent zombie processes
    def cancel_orchestrator_job(agentable)
      job_id = agentable.orchestrator_job_id
      return false unless job_id

      # Check scheduled jobs
      Sidekiq::ScheduledSet.new.each do |job|
        if job.jid == job_id
          job.delete
          Rails.logger.info("[HealthMonitor] Deleted scheduled Sidekiq job #{job_id} for #{agentable.class.name}##{agentable.id}")
          return true
        end
      end

      # Check queued jobs
      Sidekiq::Queue.new('default').each do |job|
        if job.jid == job_id
          job.delete
          Rails.logger.info("[HealthMonitor] Deleted queued Sidekiq job #{job_id} for #{agentable.class.name}##{agentable.id}")
          return true
        end
      end

      # Check running jobs (can't cancel, but log for visibility)
      Sidekiq::Workers.new.each do |process_id, thread_id, work|
        if work['payload']['jid'] == job_id
          Rails.logger.warn("[HealthMonitor] Job #{job_id} is currently running on #{process_id}/#{thread_id} - cannot cancel, but releasing lock")
          return false
        end
      end

      # Job not found anywhere - likely already completed or lost
      Rails.logger.info("[HealthMonitor] Job #{job_id} not found in Sidekiq (already completed or lost)")
      false
    end

    def publish_goal_updated(goal)
      channel = Streams::Channels.global_for_user(user: goal.user)
      Streams::Broker.publish(
        channel,
        event: 'goal_updated',
        data: {
          goal_id: goal.id,
          title: goal.title,
          status: goal.status,
          updated_at: Time.current.iso8601
        }
      )
    end
  end
end
