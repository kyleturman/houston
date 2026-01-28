# frozen_string_literal: true

# Job to execute an agent check-in
# Triggered when a scheduled check-in or follow-up time arrives
#
# Goals have two types of check-ins:
#   - scheduled: Recurring check-ins based on check_in_schedule (daily, weekly, etc.)
#   - follow_up: One-time contextual follow-ups stored in next_follow_up
#
# When a check-in fires:
#   - Removes itself from runtime_state
#   - Triggers orchestrator with check-in context
#   - For scheduled: automatically schedules the next occurrence
class AgentCheckInJob
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  # Execute the check-in
  # @param agentable_type [String] - Class name of the agentable (e.g., "Goal")
  # @param agentable_id [Integer] - ID of the agentable
  # @param slot [String] - Check-in type ("scheduled", "follow_up", or legacy "short_term"/"long_term")
  # @param check_in_data [Hash] - Check-in metadata (intent, created_at)
  def perform(agentable_type, agentable_id, slot, check_in_data)
    agentable = agentable_type.constantize.find_by(id: agentable_id)

    unless agentable
      Rails.logger.warn("[AgentCheckInJob] Agentable not found: #{agentable_type}##{agentable_id}")
      return
    end

    # Normalize slot for backward compatibility
    normalized_slot = normalize_slot(slot)

    # Remove the check-in from runtime_state (it's firing now)
    agentable.clear_check_in_for_slot!(normalized_slot)

    # If this is a scheduled check-in, schedule the next occurrence
    if normalized_slot == 'scheduled' && agentable.is_a?(Goal) && agentable.has_check_in_schedule?
      schedule_next_occurrence(agentable)
    end

    # Broadcast goal_updated so iOS knows the check-in is firing
    publish_goal_updated(agentable) if agentable.is_a?(Goal)

    # Trigger orchestrator with check-in context
    Agents::Orchestrator.perform_async(
      agentable_type,
      agentable_id,
      {
        'type' => 'agent_check_in',
        'check_in' => check_in_data.merge('slot' => normalized_slot)
      }
    )

    Rails.logger.info("[AgentCheckInJob] Triggered #{normalized_slot} check-in for #{agentable_type}##{agentable_id}: #{check_in_data['intent']}")
  end

  private

  # Normalize slot key for backward compatibility
  def normalize_slot(slot)
    case slot
    when 'scheduled', 'follow_up'
      slot
    when 'short_term', 'delay', 'delay_based'
      'follow_up'  # Legacy: treat as follow-up
    when 'long_term', 'recurring'
      'follow_up'  # Legacy: treat as follow-up
    else
      Rails.logger.warn("[AgentCheckInJob] Unknown slot type: #{slot}, defaulting to follow_up")
      'follow_up'
    end
  end

  def schedule_next_occurrence(goal)
    calculator = Goals::ScheduleCalculator.new(goal)
    calculator.schedule_next_check_in!
  rescue => e
    Rails.logger.error("[AgentCheckInJob] Failed to schedule next occurrence for Goal##{goal.id}: #{e.message}")
  end

  def publish_goal_updated(goal)
    # Build next check-in info
    next_check_in = nil
    candidates = []

    if (scheduled = goal.scheduled_check_in)
      candidates << {
        type: 'scheduled',
        scheduled_for: scheduled['scheduled_for'],
        intent: scheduled['intent']
      }
    end

    if (follow_up = goal.next_follow_up)
      candidates << {
        type: 'follow_up',
        scheduled_for: follow_up['scheduled_for'],
        intent: follow_up['intent']
      }
    end

    next_check_in = candidates.min_by { |c| Time.parse(c[:scheduled_for]) } if candidates.any?

    channel = Streams::Channels.global_for_user(user: goal.user)
    Streams::Broker.publish(
      channel,
      event: 'goal_updated',
      data: {
        goal_id: goal.id,
        title: goal.title,
        status: goal.status,
        updated_at: Time.current.iso8601,
        next_check_in: next_check_in,
        check_in_schedule: goal.check_in_schedule
      }
    )
  end
end
