# frozen_string_literal: true

module Jobs
  # Centralized job scheduling service
  # Provides a unified interface for all background job scheduling with:
  # - Deduplication
  # - Verification support
  # - Consistent logging
  # - Error handling
  class Scheduler
    class << self
      # Schedule orchestrator job
      # @param agentable [Goal, AgentTask, UserAgent] - The agentable to run orchestrator for
      # @param context [Hash] - Context hash (type, check_in data, etc.)
      # @param delay [Integer, nil] - Optional delay in seconds
      # @return [String] - Sidekiq job ID
      def schedule_orchestrator(agentable, context = {}, delay: nil)
        validate_agentable!(agentable)

        if delay
          job_id = Agents::Orchestrator.perform_in(delay.seconds, agentable.class.name, agentable.id, context)
        else
          job_id = Agents::Orchestrator.perform_async(agentable.class.name, agentable.id, context)
        end

        Rails.logger.info(
          "[Jobs::Scheduler] Scheduled Orchestrator for #{agentable.class.name}##{agentable.id}" \
          "#{delay ? " in #{delay}s" : ''} (job_id: #{job_id})"
        )

        job_id
      end

      # Schedule a check-in for a goal
      # @param agentable [Goal] - The goal to schedule check-in for
      # @param type [String] - Check-in slot: 'short_term', 'long_term', 'delay' (legacy), or 'recurring' (legacy)
      # @param scheduled_time [Time] - When to run the check-in
      # @param intent [String] - Check-in intent
      # @return [String] - Sidekiq job ID
      def schedule_check_in(agentable, type, scheduled_time, intent)
        validate_agentable!(agentable)
        raise ArgumentError, 'Only goals can have check-ins' unless agentable.goal?

        check_in_data = {
          'intent' => intent,
          'created_at' => Time.current.iso8601
        }

        job_id = AgentCheckInJob.perform_at(
          scheduled_time,
          agentable.class.name,
          agentable.id,
          type,
          check_in_data
        )

        Rails.logger.info(
          "[Jobs::Scheduler] Scheduled #{type} check-in for Goal##{agentable.id} " \
          "at #{scheduled_time.iso8601} (job_id: #{job_id})"
        )

        job_id
      end

      # Schedule feed insight generation
      # @param user_agent [UserAgent] - The user agent to generate insights for
      # @param period [String] - 'morning', 'afternoon', or 'evening'
      # @param scheduled_time [Time] - When to generate insights
      # @return [String] - Sidekiq job ID
      def schedule_feed_insights(user_agent, period, scheduled_time)
        raise ArgumentError, 'user_agent must be a UserAgent' unless user_agent.is_a?(UserAgent)

        job_id = GenerateFeedInsightsJob.perform_at(
          scheduled_time,
          user_agent.user_id,
          period
        )

        Rails.logger.info(
          "[Jobs::Scheduler] Scheduled #{period} feed insights for user #{user_agent.user_id} " \
          "at #{scheduled_time.iso8601} (job_id: #{job_id})"
        )

        job_id
      end

      # Cancel a scheduled job
      # @param job_id [String] - Sidekiq job ID
      # @return [Boolean] - true if cancelled, false if not found
      def cancel(job_id)
        return false if job_id.blank?

        scheduled_set = Sidekiq::ScheduledSet.new
        job = scheduled_set.find_job(job_id)

        if job
          job.delete
          Rails.logger.info("[Jobs::Scheduler] Cancelled job #{job_id}")
          true
        else
          Rails.logger.warn("[Jobs::Scheduler] Job #{job_id} not found in scheduled set")
          false
        end
      rescue StandardError => e
        Rails.logger.error("[Jobs::Scheduler] Failed to cancel job #{job_id}: #{e.message}")
        false
      end

      private

      def validate_agentable!(agentable)
        valid_types = ['Goal', 'AgentTask', 'UserAgent']
        unless valid_types.include?(agentable.class.name)
          raise ArgumentError, "agentable must be one of: #{valid_types.join(', ')}"
        end
      end
    end
  end
end
