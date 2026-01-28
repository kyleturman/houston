# frozen_string_literal: true

class Api::ThreadMessagesController < Api::BaseController
  include SSEStreaming
  before_action :load_parent!, except: [:retry, :destroy]
  before_action :load_error_message!, only: [:retry, :destroy]

  # GET /api/goals/:goal_id/thread/messages
  # GET /api/agent_tasks/:agent_task_id/thread/messages
  # GET /api/user_agent/thread/messages
  # Supports optional pagination via session_count parameter
  def index
    if params[:session_count].present?
      render_paginated_sessions(params[:session_count].to_i)
    else
      # Legacy: all messages (for backward compatibility)
      msgs = ThreadMessage
        .where(user_id: current_user.id, agentable: @agentable)
        .order(created_at: :asc)
      render json: ThreadMessageSerializer.new(msgs).serializable_hash
    end
  end

  # POST /api/goals/:goal_id/thread/messages
  # POST /api/agent_tasks/:agent_task_id/thread/messages
  # POST /api/user_agent/thread/messages
  def create
    content = params.require(:message).to_s
    if content.blank?
      return render json: { errors: ['message cannot be blank'] }, status: :unprocessable_entity
    end

    # Check if agentable can accept messages
    unless @agentable.accepts_messages?
      if rejection_reason = @agentable.message_rejection_reason
        return render json: { error: rejection_reason }, status: :unprocessable_entity
      end
    end

    Rails.logger.info("[ThreadMessagesController#create] user=#{current_user.id} agentable=#{@agentable.class.name}:#{@agentable.id}")

    msg = ThreadMessage.create!(
      user: current_user,
      agentable: @agentable,
      source: :user,
      content: content,
      processed: false,
      metadata: { chat_context: chat_context_meta }
    )
    Rails.logger.info("[ThreadMessagesController#create] created message id=#{msg.id}")

    # For goals, transition to working status when user sends message
    if @agentable.goal? && @agentable.waiting?
      @agentable.update!(status: :working)
    end

    # Publish immediate "processing" feedback to SSE before queueing job
    # This gives instant visual feedback while Sidekiq picks up the job
    channel = @agentable.streaming_channel
    Streams::Broker.publish(channel, event: :processing, data: { message_id: msg.id })

    kick_orchestrator!(@agentable)

    render json: ThreadMessageSerializer.new(msg).serializable_hash, status: :created
  end

  # POST /api/thread_messages/:id/retry
  # Retries the user message that triggered an error message
  def retry
    # Get triggering message IDs from error metadata
    triggering_ids = @error_message.metadata['triggering_message_ids'] || []

    if triggering_ids.empty?
      # Fallback: find the most recent user message before this error
      triggering_message = ThreadMessage
        .where(user_id: current_user.id, agentable: @agentable)
        .where(source: :user)
        .where('created_at < ?', @error_message.created_at)
        .order(created_at: :desc)
        .first

      if triggering_message.nil?
        return render json: { error: 'No user message found to retry' }, status: :unprocessable_entity
      end

      triggering_ids = [triggering_message.id]
    end

    # Mark triggering messages as unprocessed
    ThreadMessage.mark_unprocessed!(triggering_ids)

    # Delete the error message
    @error_message.destroy!

    # Kick orchestrator
    if @agentable.should_start_orchestrator?
      Agents::Orchestrator.perform_async(@agentable.class.name, @agentable.id)
    end

    Rails.logger.info("[ThreadMessagesController#retry] Retried message(s) #{triggering_ids} for #{@agentable.class.name}##{@agentable.id}")

    render json: {
      success: true,
      retried_message_ids: triggering_ids.map(&:to_s)
    }, status: :ok
  end

  # DELETE /api/thread_messages/:id
  # Dismisses (deletes) an error message
  def destroy
    @error_message.destroy!

    Rails.logger.info("[ThreadMessagesController#destroy] Dismissed error message #{params[:id]} for #{@agentable.class.name}##{@agentable.id}")

    render json: { success: true }, status: :ok
  end

  # GET /api/goals/:goal_id/thread/stream
  # GET /api/agent_tasks/:agent_task_id/thread/stream
  # GET /api/user_agent/thread/stream
  def stream
    # Set SSE headers before any streaming writes
    set_sse_headers

    # Handle cases where agentable is not active
    unless @agentable.agent_active?
      if @agentable.task? && @agentable.completed?
        sse_write(event: 'task_completed', data: { 
          message: 'Task has been completed', 
          task_id: @agentable.id,
          status: 'completed'
        })
        response.stream.close
        return
      end

      if @agentable.goal? && @agentable.archived?
        sse_write(event: 'goal_archived', data: { 
          message: 'Goal has been archived', 
          goal_id: @agentable.id,
          status: 'archived'
        })
        response.stream.close
        return
      end

      render json: { error: 'No active agent available for streaming' }, status: :unprocessable_entity
      return
    end

    channel = @agentable.streaming_channel
    Rails.logger.info("[ThreadMessagesController#stream] user=#{current_user.id} channel=#{channel} start")
    
    sub = nil
    stream_thread = nil
    
    begin
      # Set up subscription with timeout protection
      sub = Timeout.timeout(10) do
        Streams::Broker.subscribe(channel)
      end
      
      sse_write(event: Streams::Channels::WELCOME, data: { channel: channel })
      started_at = Time.now
      last_heartbeat_at = Time.now
      last_activity_at = Time.now
      heartbeat_every = 30 # seconds - send keepalive events (reduced from 20 to lower server load)
      max_duration = 600   # seconds; force reconnect periodically to avoid zombie threads (10 min)
      max_idle_time = 300  # seconds; close if no activity for 5 minutes
      
      # Use a separate thread to handle the stream with timeout protection
      stream_thread = Thread.new do
        loop do
          break if response.stream.closed?
          
          # Check for timeouts
          now = Time.now
          if (now - started_at) >= max_duration
            Rails.logger.info("[ThreadMessagesController#stream] user=#{current_user.id} max duration reached")
            break
          end
          
          if (now - last_activity_at) >= max_idle_time
            Rails.logger.info("[ThreadMessagesController#stream] user=#{current_user.id} idle timeout")
            break
          end
          
          # Blocking pop with short timeout for responsive streaming
          # Using blocking pop avoids polling delays - messages are sent immediately when they arrive
          payload = nil
          begin
            Timeout.timeout(1.0) do
              payload = sub.queue.pop  # Blocking pop - wakes immediately when message arrives
            end
            last_activity_at = Time.now if payload
          rescue Timeout::Error
            # No message in 1 second - check timeouts and maybe send heartbeat
          end

          if payload
            event = Utils::HashAccessor.hash_get(payload, :event)
            data  = Utils::HashAccessor.hash_get_hash(payload, :data)
            Rails.logger.debug("[ThreadMessagesController#stream] user=#{current_user.id} event=#{event}")

            begin
              sse_write(event: event, data: data)
            rescue ActionController::Live::ClientDisconnected, IOError => e
              Rails.logger.debug("[ThreadMessagesController#stream] client disconnected during write: #{e.message}")
              break
            rescue => e
              Rails.logger.warn("[ThreadMessagesController#stream] write error: #{e.message}")
              break
            end
          else
            # No message received in timeout period - send keepalive if needed
            now = Time.now
            if (now - last_heartbeat_at) >= heartbeat_every
              begin
                # Send proper SSE keepalive event instead of comment
                sse_write(event: 'keepalive', data: { timestamp: now.to_i })
                last_heartbeat_at = now
                Rails.logger.debug("[ThreadMessagesController#stream] keepalive sent")
              rescue ActionController::Live::ClientDisconnected, IOError => e
                Rails.logger.debug("[ThreadMessagesController#stream] client disconnected during keepalive")
                break
              rescue => e
                Rails.logger.warn("[ThreadMessagesController#stream] keepalive failed: #{e.message}")
                break
              end
            end
            # No sleep needed - blocking pop handles the wait
          end
        end
      end
      
      # Wait for the stream thread with overall timeout
      stream_thread.join(max_duration + 10)
      
    rescue Timeout::Error => e
      Rails.logger.error("[ThreadMessagesController#stream] timeout error: #{e.message}")
    rescue ActionController::Live::ClientDisconnected, IOError => e
      Rails.logger.info("[ThreadMessagesController#stream] client disconnected: #{e.message}")
    rescue => e
      Rails.logger.error("[ThreadMessagesController#stream] unexpected error: #{e.message}")
    ensure
      # Cleanup with timeout protection
      begin
        Timeout.timeout(5) do
          Rails.logger.info("[ThreadMessagesController#stream] user=#{current_user.id} channel=#{channel} closed")
          
          # Kill stream thread if still alive
          if stream_thread&.alive?
            stream_thread.kill
            stream_thread.join(1)
          end
          
          # Unsubscribe from broker
          Streams::Broker.unsubscribe(channel, sub) if sub
          
          # Close response stream
          response.stream.close unless response.stream.closed?
        end
      rescue Timeout::Error
        Rails.logger.error("[ThreadMessagesController#stream] cleanup timeout for user=#{current_user.id}")
        # Force cleanup
        stream_thread&.kill
        begin
          response.stream.close
        rescue
          # ignore
        end
      rescue => e
        Rails.logger.error("[ThreadMessagesController#stream] cleanup error: #{e.message}")
      end
    end
  end

  private

  def render_paginated_sessions(session_count)
    # Load current session + N previous archived sessions
    archived_sessions = @agentable.agent_histories
      .order(completed_at: :desc)
      .limit([session_count - 1, 0].max)
      .pluck(:id)

    # Get messages from selected sessions OR current session (agent_history_id = nil)
    msgs = ThreadMessage
      .where(user_id: current_user.id, agentable: @agentable)
      .where('agent_history_id IN (?) OR agent_history_id IS NULL', archived_sessions.presence || [nil])
      .order(created_at: :asc)

    total_sessions = @agentable.agent_histories.count + 1 # +1 for current session

    render json: {
      data: ThreadMessageSerializer.new(msgs).serializable_hash[:data],
      meta: {
        total_sessions: total_sessions,
        loaded_sessions: [session_count, total_sessions].min,
        has_more: total_sessions > session_count
      }
    }
  end

  def load_parent!
    @agentable = if params[:goal_id]
      current_user.goals.find_by(id: params[:goal_id])
    elsif params[:agent_task_id]
      AgentTask.where(user_id: current_user.id).find_by(id: params[:agent_task_id])
    elsif params[:user_agent_id] || request.path.include?('/user_agent/')
      current_user.user_agent
    end

    unless @agentable
      type_name = params[:goal_id] ? 'Goal' : params[:agent_task_id] ? 'Task' : 'User Agent'
      return render json: { errors: ["#{type_name} not found"] }, status: :not_found
    end
  end

  # Load error message for retry/destroy actions (standalone routes)
  def load_error_message!
    @error_message = ThreadMessage.find_by(id: params[:id], user_id: current_user.id)

    unless @error_message
      return render json: { error: 'Message not found' }, status: :not_found
    end

    unless @error_message.error?
      return render json: { error: 'Only error messages can be retried or dismissed' }, status: :unprocessable_entity
    end

    # Load the agentable from the message
    @agentable = @error_message.agentable
  end

  def chat_context_meta
    case @agentable.agent_type
    when 'goal'
      { type: 'goal', goal_id: @agentable.id }
    when 'task'
      { type: 'task', goal_id: @agentable.goal_id, agent_task_id: @agentable.id }
    when 'user_agent'
      { type: 'user_agent', user_agent_id: @agentable.id }
    end
  end

  def ensure_agentable!
    # Return agentable if it's active, otherwise nil
    @agentable&.agent_active? ? @agentable : nil
  end

  def kick_orchestrator!(agentable)
    return unless agentable.should_start_orchestrator?
    # Unified orchestrator handles all agent types
    Agents::Orchestrator.perform_async(agentable.class.name, agentable.id)
  end

  # Use sse_write_event from SSEStreaming concern
  alias_method :sse_write, :sse_write_event
end
