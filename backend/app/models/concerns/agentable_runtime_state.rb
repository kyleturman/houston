# frozen_string_literal: true

# AgentableRuntimeState provides named getter/setter methods for the runtime_state
# JSONB column on agentable models. This keeps Agentable focused on agent behavior
# while centralizing all state access through a clean, discoverable interface.
#
# This concern is internal to Agentable — do not include it in non-agentable models.
# All methods here delegate to update_runtime_state! (defined in Agentable) for writes,
# ensuring atomic read-modify-write semantics. Readers are simple hash lookups.
#
# See Agentable for the full runtime_state key inventory.
module AgentableRuntimeState
  extend ActiveSupport::Concern

  # ===========================================================================
  # Orchestrator Lifecycle
  # ===========================================================================

  def agent_running?
    runtime_state&.dig('orchestrator_running') == true
  end

  def orchestrator_started_at
    runtime_state&.dig('orchestrator_started_at')
  end

  def orchestrator_job_id
    runtime_state&.dig('orchestrator_job_id')
  end

  # Claim execution lock to prevent duplicate orchestrators.
  # Returns true if lock was claimed, false if already running.
  def claim_execution_lock!
    update_runtime_state!(with_lock: true) do |state|
      return false if state['orchestrator_running'] == true

      state['orchestrator_running'] = true
      state['orchestrator_started_at'] = Time.current.iso8601
    end
    true
  end

  # Release execution lock after orchestrator completes.
  def release_execution_lock!
    update_runtime_state! do |state|
      state['orchestrator_running'] = false
      state.delete('orchestrator_job_id')
    end
  end

  def set_orchestrator_job_id!(job_id)
    update_runtime_state! do |state|
      state['orchestrator_job_id'] = job_id
    end
  end

  # ===========================================================================
  # Session Management
  # ===========================================================================

  def current_turn_started_at
    runtime_state&.dig('current_turn_started_at')
  end

  # Start or continue a session (idempotent — won't reset an existing timestamp)
  def start_agent_turn_if_needed!
    return if current_turn_started_at.present?

    update_runtime_state! do |state|
      state['current_turn_started_at'] = Time.current.iso8601
    end
  end

  def feed_period
    runtime_state&.dig('current_feed_period')
  end

  def set_feed_period!(period)
    update_runtime_state! do |state|
      state['current_feed_period'] = period
    end
  end

  # Clear ephemeral session keys after a turn completes or is archived.
  # Called by archive_agent_turn! — kept as a named method for clarity.
  def clear_session_keys(state)
    state.delete('current_turn_started_at')
    state.delete('current_feed_period')
  end

  # ===========================================================================
  # Check-in State (Goal only)
  # ===========================================================================

  def scheduled_check_in
    runtime_state&.dig('scheduled_check_in')
  end

  def set_scheduled_check_in!(data)
    update_runtime_state! do |state|
      state['scheduled_check_in'] = data
    end
  end

  def clear_scheduled_check_in!
    update_runtime_state! do |state|
      state.delete('scheduled_check_in')
    end
  end

  def next_follow_up
    runtime_state&.dig('next_follow_up')
  end

  def set_next_follow_up!(data)
    update_runtime_state! do |state|
      state['next_follow_up'] = data
    end
  end

  def clear_next_follow_up!
    update_runtime_state! do |state|
      state.delete('next_follow_up')
    end
  end

  def original_follow_up
    runtime_state&.dig('original_follow_up')
  end

  def set_original_follow_up!(data)
    update_runtime_state! do |state|
      state['original_follow_up'] = data
    end
  end

  def clear_original_follow_up!
    update_runtime_state! do |state|
      state.delete('original_follow_up')
    end
  end

  def check_in_last_adjusted_at
    runtime_state&.dig('check_in_last_adjusted_at')
  end

  def set_check_in_last_adjusted_at!
    update_runtime_state! do |state|
      state['check_in_last_adjusted_at'] = Time.current.iso8601
    end
  end

  # Clear check-in state when a check-in fires.
  def clear_check_in_for_slot!(slot)
    update_runtime_state! do |state|
      case slot
      when 'scheduled'
        state.delete('scheduled_check_in')
      when 'follow_up'
        state.delete('next_follow_up')
        state.delete('original_follow_up')
      end
    end
  end

  # ===========================================================================
  # Feed State (UserAgent only)
  # ===========================================================================

  def feed_schedule
    runtime_state&.dig('feed_schedule')
  end

  def feed_attempts_for(period)
    runtime_state&.dig('feed_attempts', period)
  end

  # Get attempt count for a period within a rolling 24-hour window.
  # Auto-resets to 0 if the last recorded attempt is older than 24 hours.
  # @param period [String] 'morning', 'afternoon', or 'evening'
  # @return [Integer] current attempt count
  def feed_attempt_count(period)
    attempts = feed_attempts_for(period)
    return 0 unless attempts

    recorded_at = attempts['recorded_at']
    return 0 unless recorded_at
    return 0 if Time.parse(recorded_at) < 24.hours.ago

    attempts['count'] || 0
  end

  # Record a feed generation attempt with timestamp.
  # Uses a 24-hour rolling window — count auto-resets after 24 hours.
  # @param period [String] 'morning', 'afternoon', or 'evening'
  def record_feed_attempt!(period)
    update_runtime_state!(with_lock: true) do |state|
      state['feed_attempts'] ||= {}
      existing = state['feed_attempts'][period] || {}

      # Check if we need to reset (no recorded_at, or older than 24 hours)
      recorded_at = existing['recorded_at']
      should_reset = recorded_at.nil? || Time.parse(recorded_at) < 24.hours.ago

      if should_reset
        state['feed_attempts'][period] = {
          'recorded_at' => Time.current.iso8601,
          'count' => 1
        }
      else
        existing['count'] = (existing['count'] || 0) + 1
        existing['recorded_at'] = Time.current.iso8601
        state['feed_attempts'][period] = existing
      end
    end
  end
end
