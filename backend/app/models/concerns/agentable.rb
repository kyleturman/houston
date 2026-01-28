# frozen_string_literal: true

# Agentable concern provides shared agent functionality for Goal, AgentTask, and UserAgent models.
# This eliminates the need for a separate AgentInstance model by making models directly agentable.
#
# ===========================================================================
# Runtime State Key Inventory
# ===========================================================================
# runtime_state is a JSONB column storing ephemeral operational state.
# All access should go through named methods below — avoid direct hash manipulation.
#
# ORCHESTRATOR LIFECYCLE (all agentable types):
#   orchestrator_running       [bool]    - execution lock flag
#   orchestrator_started_at    [ISO8601] - when lock was claimed (for timeout detection)
#   orchestrator_job_id        [string]  - Sidekiq JID (for job cancellation by HealthMonitor)
#
# SESSION MANAGEMENT (all agentable types):
#   current_turn_started_at    [ISO8601] - when current agent session began
#   current_feed_period        [string]  - feed period context ('morning'/'afternoon'/'evening')
#
# CHECK-IN STATE (Goal only):
#   scheduled_check_in         [hash]    - {job_id, scheduled_for, intent, created_at}
#   next_follow_up             [hash]    - {job_id, scheduled_for, intent, created_at}
#   original_follow_up         [hash]    - {scheduled_for, intent, stored_at} (note-triggered reschedule)
#   check_in_last_adjusted_at  [ISO8601] - debounce timestamp for note-triggered check-ins
#
# FEED STATE (UserAgent only):
#   feed_schedule              [hash]    - {enabled, periods, jobs} (managed by InsightScheduler)
#   feed_attempts              [hash]    - {period => {recorded_at, count}} (24hr rolling window)
# ===========================================================================
module Agentable
  extend ActiveSupport::Concern

  included do
    include AgentableRuntimeState

    # Agent-related associations
    has_many :thread_messages, as: :agentable, dependent: :destroy
    has_many :agent_histories, as: :agentable, dependent: :destroy

    # Agent state and history fields
    attribute :runtime_state, :json, default: {}
    attribute :llm_history, :json, default: []
  end

  # ===========================================================================
  # Agent Type Identification
  # ===========================================================================

  def agent_type
    case self.class.name
    when 'Goal'
      'goal'
    when 'AgentTask'
      'task'
    when 'UserAgent'
      'user_agent'
    else
      raise "Unknown agentable type: #{self.class.name}"
    end
  end

  def goal?
    agent_type == 'goal'
  end

  def task?
    agent_type == 'task'
  end

  def user_agent?
    agent_type == 'user_agent'
  end

  # Agent behavior - tasks are autonomous, goals/user_agents are conversational
  def conversational?
    !task?
  end

  # Returns the associated goal for this agentable
  # - Goal: returns itself
  # - AgentTask: returns its parent goal
  # - UserAgent: returns nil (has no associated goal)
  def associated_goal
    case self
    when Goal
      self
    when AgentTask
      goal
    when UserAgent
      nil
    else
      raise "Unknown agentable type: #{self.class.name}"
    end
  end

  # ===========================================================================
  # Agent Status
  # ===========================================================================

  def agent_active?
    case agent_type
    when 'goal'
      !archived?
    when 'task'
      active? || paused?
    when 'user_agent'
      true
    end
  end

  def accepts_messages?
    case agent_type
    when 'goal'
      !archived?
    when 'task'
      !cancelled? && !completed?
    when 'user_agent'
      true
    end
  end

  def message_rejection_reason
    return nil if accepts_messages?

    case agent_type
    when 'goal'
      'Goal is archived and cannot receive messages.' if archived?
    when 'task'
      if paused?
        'Task is paused and cannot receive messages. Please retry the task first.'
      elsif cancelled?
        'Task is cancelled and cannot receive messages.'
      elsif completed?
        nil # Allow messages to completed tasks (no orchestrator kickoff)
      end
    end
  end

  def should_start_orchestrator?
    case agent_type
    when 'goal'
      !archived?
    when 'task'
      agent_active? && !completed?
    when 'user_agent'
      true
    end
  end

  def streaming_channel
    Streams::Channels.for_agentable(agentable: self)
  end

  def can_execute?
    agent_active? && !agent_running?
  end

  # ===========================================================================
  # Runtime State: Atomic Update Helper
  # ===========================================================================
  # Shared helper for safe read-modify-write of runtime_state.
  # Yields the current state hash; caller mutates it in place.
  # Always writes back with update_column (skips validations/callbacks for performance).
  #
  # Use with_lock: true when concurrent writes are possible (e.g., claim_execution_lock!).
  #
  # External services (InsightScheduler, GenerationGuard) may call this for complex
  # nested state that doesn't warrant individual accessor methods. Prefer named
  # accessor methods where they exist.
  def update_runtime_state!(with_lock: false)
    if with_lock
      self.with_lock do
        state = (reload.runtime_state || {}).dup
        yield state
        update_column(:runtime_state, state)
      end
    else
      state = (runtime_state || {}).dup
      yield state
      update_column(:runtime_state, state)
    end
  end

  # ===========================================================================
  # LLM History Management
  # ===========================================================================

  def add_to_llm_history(message)
    current = llm_history || []
    current << message

    # Keep only last 100 messages to prevent unbounded growth
    trimmed = current.length > 100 ? current.last(100) : current

    update_column(:llm_history, trimmed)
  end

  def get_llm_history
    llm_history || []
  end

  def trim_llm_history(keep_last: 50)
    current_history = llm_history || []
    if current_history.length > keep_last
      trimmed_history = current_history.last(keep_last)
      update!(llm_history: trimmed_history)
    end
  end

  # ===========================================================================
  # Thread Message Context
  # ===========================================================================

  def recent_message_context(days: 15)
    cutoff = days.days.ago
    thread_messages
      .where('created_at > ?', cutoff)
      .order(:created_at)
      .select(:content, :source, :created_at)
      .map { |msg|
        "#{msg.source.upcase} (#{msg.created_at.strftime('%m/%d %H:%M')}): #{msg.content}"
      }
      .join("\n")
  end

  def unprocessed_thread_messages
    thread_messages.unprocessed.for_context
  end

  # ===========================================================================
  # Learning Management - Shared across Goal and UserAgent
  # ===========================================================================

  def add_learning(content)
    current_learnings = learnings || []
    learning_id = SecureRandom.uuid
    current_learnings << {
      id: learning_id,
      content: content,
      created_at: Time.current.iso8601
    }
    update!(learnings: current_learnings)
    learning_id
  end

  def update_learning(learning_id, content: nil)
    current_learnings = learnings || []
    learning = current_learnings.find { |l| l['id'] == learning_id || l[:id] == learning_id }
    return false unless learning

    learning['content'] = content if content.present?
    learning['updated_at'] = Time.current.iso8601

    update!(learnings: current_learnings)
    true
  end

  def remove_learning(learning_id)
    current_learnings = learnings || []
    initial_size = current_learnings.size
    current_learnings.reject! { |l| l['id'] == learning_id || l[:id] == learning_id }

    return false if current_learnings.size == initial_size

    update!(learnings: current_learnings)
    true
  end

  def find_learning(learning_id)
    return nil unless learnings
    learnings.find { |l| l['id'] == learning_id || l[:id] == learning_id }
  end

  # ===========================================================================
  # Agent History Management - Session archiving and retrieval
  # ===========================================================================

  # Minimum number of thread messages required before archiving a session.
  # Sessions with fewer messages are not worth summarizing and storing.
  MINIMUM_THREAD_MESSAGES_FOR_ARCHIVE = 12

  # Maximum age of a session before it gets archived regardless of message count.
  MAXIMUM_SESSION_AGE_FOR_ARCHIVE = 24.hours

  # Archive current session to agent_histories and clear llm_history
  def archive_agent_turn!(reason:)
    current_history = llm_history || []
    return if current_history.empty?

    # Autonomous sessions are identified by their completion reason, not content analysis
    # (content analysis is unreliable because system prompts get stored as 'user' messages)
    is_autonomous = Agents::Constants::AUTONOMOUS_ARCHIVE_REASONS.include?(reason)

    current_thread_message_count = thread_messages.current_session.count
    session_started_at = current_turn_started_at&.to_time
    session_age = session_started_at ? (Time.current - session_started_at) : 0

    # Autonomous sessions (feed generation, check-ins) should always be archived
    # so the agent remembers what it did. Conversational sessions need enough
    # messages to be worth summarizing.
    should_archive = if is_autonomous
                       # Archive autonomous sessions if they have meaningful content (tool calls)
                       current_history.any? { |m|
                         m['content'].is_a?(Array) && m['content'].any? { |c| c['type'] == 'tool_use' }
                       }
                     else
                       # Archive conversational sessions if:
                       # 1. Enough thread messages to be worth saving, OR
                       # 2. Session is old enough that we should clear it regardless
                       current_thread_message_count >= MINIMUM_THREAD_MESSAGES_FOR_ARCHIVE ||
                         (session_started_at && session_age >= MAXIMUM_SESSION_AGE_FOR_ARCHIVE)
                     end

    unless should_archive
      log_msg = if is_autonomous
                  "[Agentable] Skipping archive for #{self.class.name}##{id}: autonomous session with no tool calls"
                else
                  "[Agentable] Skipping archive for #{self.class.name}##{id}: " \
                  "only #{current_thread_message_count} thread messages (minimum: #{MINIMUM_THREAD_MESSAGES_FOR_ARCHIVE}) " \
                  "and session age #{(session_age / 1.hour).round(1)}h (minimum: #{MAXIMUM_SESSION_AGE_FOR_ARCHIVE / 1.hour}h)"
                end
      Rails.logger.info(log_msg)

      # Still clear llm_history and session keys to prevent unbounded growth
      cleared_state = (runtime_state || {}).dup
      clear_session_keys(cleared_state)
      update_columns(llm_history: [], runtime_state: cleared_state)
      return
    end

    summary = generate_turn_summary(current_history)

    agent_history = agent_histories.create!(
      agent_history: current_history,
      summary: summary,
      completion_reason: reason,
      message_count: current_history.length,
      token_count: estimate_tokens(current_history),
      started_at: current_turn_started_at || Time.current,
      completed_at: Time.current
    )

    # Associate all current session ThreadMessages with this agent_history
    thread_messages.current_session.update_all(
      agent_history_id: agent_history.id,
      updated_at: Time.current
    )

    # Clear for next session
    cleared_state = (runtime_state || {}).dup
    clear_session_keys(cleared_state)
    update_columns(llm_history: [], runtime_state: cleared_state)

    Rails.logger.info(
      "[Agentable] Archived #{current_history.length} messages " \
      "for #{self.class.name}##{id}, reason: #{reason}"
    )
  end

  # Generate summary using LLM or fallback to user messages
  def generate_turn_summary(history)
    tool_names = extract_tool_names(history)

    system = Llms::Prompts::AgentHistory.system_prompt
    user = Llms::Prompts::AgentHistory.user_prompt(
      llm_history: history,
      tool_names: tool_names
    )

    result = Llms::Service.call(
      system: system,
      messages: [{role: "user", content: user}],
      user: self.user,
      use_case: :summaries
    )

    extract_text_from_result(result)
  rescue => e
    Rails.logger.error("[Agentable] Summary generation failed: #{e.message}")
    fallback_summary_from_user_messages(history)
  end

  # Fallback: Extract user questions if summarization fails
  def fallback_summary_from_user_messages(history)
    user_messages = history
      .select { |m| m['role'] == 'user' }
      .map { |m|
        content = m['content']
        text = content.is_a?(Array) ? content.to_json : content.to_s
        text.to_s
      }
      .join(' ')
      .to_s
      .truncate(200)

    if user_messages.present?
      "User asked: #{user_messages}"
    else
      "Agent session on #{Time.current.strftime('%b %d, %Y')}"
    end
  end

  # Get recent summaries for context building.
  # Handles decryption errors gracefully by skipping corrupted records.
  def recent_agent_history_summaries(limit: 5)
    results = []
    agent_histories.order(completed_at: :desc).limit(limit + 5).each do |history|
      break if results.length >= limit
      begin
        summary = history.summary
        date = history.completed_at
        results << "[#{date.strftime('%b %d')}] #{summary}" if summary.present?
      rescue ActiveRecord::Encryption::Errors::Decryption => e
        Rails.logger.warn("[Agentable] Skipping corrupted agent_history##{history.id}: #{e.message}")
        next
      end
    end
    results
  end

  private

  # Check if session has actual user messages (not just tool results or system prompts)
  def session_has_user_messages?(history)
    history.any? do |msg|
      next false unless msg['role'] == 'user'
      content = msg['content']

      next true if content.is_a?(String) && content.present?

      if content.is_a?(Array)
        content.any? { |block| block['type'] != 'tool_result' }
      else
        false
      end
    end
  end

  def extract_tool_names(history)
    history
      .select { |m| m['tool_calls'].present? }
      .flat_map { |m| m['tool_calls'].map { |tc| tc['name'] } }
      .uniq
  end

  def extract_text_from_result(result)
    result[:content]
      .select { |block| block[:type] == :text }
      .map { |block| block[:text] }
      .join("\n")
      .strip
  end

  def estimate_tokens(messages)
    messages.sum { |m| m.to_s.length } / 4
  end
end
