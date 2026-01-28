# frozen_string_literal: true

class Api::AgentHistoriesController < Api::BaseController
  before_action :load_agentable!

  # GET /api/goals/:goal_id/agent_histories
  # GET /api/user_agent/agent_histories
  def index
    histories = @agentable.agent_histories
      .order(completed_at: :desc)
      .limit(100)
    render json: AgentHistorySerializer.new(histories).serializable_hash
  end

  # GET /api/goals/:goal_id/agent_histories/:id
  # GET /api/user_agent/agent_histories/:id
  def show
    history = @agentable.agent_histories.find(params[:id])
    messages = history.thread_messages.order(created_at: :asc)

    render json: {
      data: AgentHistorySerializer.new(history).serializable_hash[:data],
      included: {
        thread_messages: ThreadMessageSerializer.new(messages).serializable_hash[:data]
      }
    }
  end

  # DELETE /api/goals/:goal_id/agent_histories/:id
  # DELETE /api/user_agent/agent_histories/:id
  def destroy
    history = @agentable.agent_histories.find(params[:id])
    history.destroy

    publish_lifecycle_event('agent_history_deleted', history)
    head :no_content
  end

  # GET /api/goals/:goal_id/agent_histories/current
  # GET /api/user_agent/agent_histories/current
  # Returns the current (in-progress) session with its thread messages
  def current
    messages = @agentable.thread_messages.current_session.order(created_at: :asc)
    message_count = messages.count
    started_at = @agentable.current_turn_started_at
    token_count = (@agentable.llm_history || []).sum { |m| m.to_s.length } / 4 rescue 0

    render json: {
      data: {
        id: 'current',
        type: 'agent_history',
        attributes: {
          summary: 'Current Session (in progress)',
          completion_reason: nil,
          message_count: message_count,
          token_count: token_count,
          agentable_type: @agentable.class.name,
          agentable_id: @agentable.id.to_s,
          started_at: started_at,
          completed_at: nil,
          created_at: nil,
          updated_at: nil,
          is_current: true
        }
      },
      included: {
        thread_messages: ThreadMessageSerializer.new(messages).serializable_hash[:data]
      }
    }
  end

  # DELETE /api/goals/:goal_id/agent_histories/current
  # DELETE /api/user_agent/agent_histories/current
  # Resets the current session by discarding llm_history and thread messages without archiving
  def reset_current
    messages_deleted = @agentable.thread_messages.current_session.count
    llm_entries_cleared = (@agentable.llm_history || []).length

    # Delete current session thread messages
    @agentable.thread_messages.current_session.destroy_all

    # Clear llm_history without archiving
    @agentable.update_columns(
      llm_history: [],
      runtime_state: (@agentable.runtime_state || {}).except('current_turn_started_at')
    )

    # Publish SSE event for real-time UI updates
    publish_reset_event(messages_deleted, llm_entries_cleared)

    head :no_content
  end

  private

  def load_agentable!
    @agentable = if params[:goal_id]
      current_user.goals.find_by(id: params[:goal_id])
    elsif params[:user_agent_id] || request.path.include?('/user_agent/')
      current_user.user_agent
    end

    unless @agentable
      type_name = params[:goal_id] ? 'Goal' : 'User Agent'
      return render json: { errors: ["#{type_name} not found"] }, status: :not_found
    end
  end

  def publish_lifecycle_event(event_name, history)
    channel = Streams::Channels.global_for_user(user: current_user)

    Streams::Broker.publish(
      channel,
      event: event_name,
      data: {
        agent_history_id: history.id,
        agentable_type: history.agentable_type,
        agentable_id: history.agentable_id
      }
    )
  rescue => e
    Rails.logger.error("[AgentHistoriesController] Failed to publish: #{e.message}")
  end

  def publish_reset_event(messages_deleted, llm_entries_cleared)
    channel = Streams::Channels.global_for_user(user: current_user)

    Streams::Broker.publish(
      channel,
      event: 'agent_session_reset',
      data: {
        agentable_type: @agentable.class.name,
        agentable_id: @agentable.id,
        messages_deleted: messages_deleted,
        llm_entries_cleared: llm_entries_cleared
      }
    )
  rescue => e
    Rails.logger.error("[AgentHistoriesController] Failed to publish reset event: #{e.message}")
  end
end
