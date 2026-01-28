# frozen_string_literal: true

class AgentTask < ApplicationRecord
  include Agentable

  belongs_to :user
  belongs_to :goal, optional: true
  belongs_to :taskable, polymorphic: true, optional: true
  belongs_to :parent_task, class_name: 'AgentTask', optional: true

  has_many :child_tasks, class_name: 'AgentTask', foreign_key: :parent_task_id, dependent: :nullify

  enum :status, { active: 0, completed: 1, paused: 2, cancelled: 3 }
  enum :priority, { low: 0, normal: 1, high: 2, critical: 3 }

  validates :title, presence: true
  validates :status, presence: true
  validates :priority, presence: true

  # Cast JSONB attribute for typed access
  attribute :context_data, :json, default: {}
  attribute :orchestrator_state, :json, default: {}
  attribute :result_data, :json, default: {}

  # Encrypt sensitive fields
  encrypts :llm_history
  encrypts :instructions

  # Start orchestrator after task creation
  after_create :start_orchestrator!
  
  # Stream task status updates
  after_update :stream_status_update, if: :saved_change_to_status?

  # Soft failure methods
  def pause_with_error!(error_type, error_message, retry_delay = nil)
    update!(
      status: :paused,
      error_type: error_type.to_s,
      error_message: error_message,
      retry_count: (retry_count || 0) + 1,
      next_retry_at: retry_delay ? Time.current + retry_delay : nil
    )
  end

  def cancel_with_reason!(reason)
    update!(
      status: :cancelled,
      cancelled_reason: reason
    )
  end

  def ready_for_retry?
    paused? && (next_retry_at.nil? || next_retry_at <= Time.current)
  end

  def retryable?
    paused? && (retry_count || 0) < max_retries_for_error_type
  end

  def user_friendly_error_message
    case error_type
    when 'rate_limit'
      'API was rate limited'
    when 'network', 'timeout'
      'Network connection issue'
    when 'mcp_error'
      'External tool error'
    else
      error_message&.truncate(100) || 'Unknown error occurred'
    end
  end

  # Get the associated goal (for polymorphic tasks)
  def associated_goal
    return goal if goal.present?
    return taskable if taskable.is_a?(Goal)
    nil
  end

  # Determine parent for streaming
  def parent_agentable
    goal || taskable
  end

  # Start the orchestrator for this task
  def start_orchestrator!
    Rails.logger.info("[AgentTask] start_orchestrator! called for task=#{id}, status=#{status}, can_execute?=#{can_execute?}")
    Rails.logger.info("[AgentTask]   agent_active?=#{agent_active?}, agent_running?=#{agent_running?}")

    unless can_execute?
      Rails.logger.warn("[AgentTask] Cannot execute task=#{id}: status=#{status}, agent_active?=#{agent_active?}, agent_running?=#{agent_running?}")
      return
    end

    begin
      # Pass context_data to orchestrator so child tasks inherit parent context
      # This ensures feed_period and other context flows through task delegation
      orchestrator_context = context_data.present? ? context_data.stringify_keys : {}
      job_id = Agents::Orchestrator.perform_in(rand(1..5).seconds, self.class.name, id, orchestrator_context)
      set_orchestrator_job_id!(job_id)
      
      Rails.logger.info("[AgentTask] Started orchestrator for task=#{id} job=#{job_id}")
      job_id
    rescue => e
      Rails.logger.error("[AgentTask] CRITICAL: Failed to start Orchestrator for task=#{id}: #{e.class}: #{e.message}")
      Rails.logger.error("[AgentTask] Backtrace: #{e.backtrace.first(5).join("\n")}")
      
      # Mark task as failed if orchestrator can't start
      update!(status: :cancelled, result_summary: "Failed to start orchestrator: #{e.message}")
      
      raise e # Re-raise to ensure the failure is visible
    end
  end

  private

  def stream_status_update
    # Stream task status update to the parent's SSE channel (goal or taskable)
    parent = parent_agentable
    return unless parent

    # Update the ThreadMessage metadata in the parent's thread
    update_task_thread_message_status

    # Publish to parent's SSE channel (per-agentable stream for real-time chat updates)
    stream_channel = Streams::Channels.for_agentable(agentable: parent)
    Streams::Broker.publish(stream_channel, event: :task_update, data: {
      task_id: id,
      status: status,
      title: title,
      updated_at: updated_at.iso8601
    })

    # Publish to global stream (for ViewModels to refresh their lists)
    event_name = completed? ? 'task_completed' : 'task_updated'
    global_channel = Streams::Channels.global_for_user(user: user)
    Streams::Broker.publish(global_channel, event: event_name, data: {
      task_id: id,
      goal_id: goal_id,  # May be nil for UserAgent tasks
      taskable_type: taskable_type,
      taskable_id: taskable_id,
      title: title,
      status: status.to_s,
      priority: priority.to_s,
      instructions: instructions.to_s.truncate(200),
      updated_at: updated_at.iso8601
    })

    Rails.logger.info("[AgentTask] Published #{event_name} to global stream for user #{user.id}")
  rescue => e
    Rails.logger.error("[AgentTask] Failed to stream status update: #{e.message}")
  end
  
  def update_task_thread_message_status
    # Find the ThreadMessage in the parent's thread that created this task
    return unless origin_tool_activity_id

    # Use indexed lookup on tool_activity_id (fast!)
    message = ThreadMessage.where(
      tool_activity_id: origin_tool_activity_id
    ).first

    unless message
      Rails.logger.warn("[AgentTask] No ThreadMessage found for task #{id} (tool_activity_id: #{origin_tool_activity_id})")
      return
    end

    # Update the task_status in the metadata (standardized structure: tool_activity.data)
    old_status = message.metadata.dig('tool_activity', 'data', 'task_status')

    # Update task_status in data
    message.update_tool_activity_data({ task_status: status.to_s })

    # Clear display_message when task completes so title shows
    if status.to_s == 'completed'
      message.delete_tool_activity_fields([:display_message])
    end

    Rails.logger.info("[AgentTask] Updated ThreadMessage #{message.id} task_status: #{old_status} → #{status}")
  rescue => e
    Rails.logger.error("[AgentTask] Failed to update ThreadMessage status: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
  end

  def max_retries_for_error_type
    case error_type&.to_sym
    when :rate_limit
      Agents::Constants::MAX_RETRIES_RATE_LIMIT
    when :network, :timeout
      Agents::Constants::MAX_RETRIES_NETWORK
    else
      Agents::Constants::MAX_RETRIES_DEFAULT
    end
  end
end
