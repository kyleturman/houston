# frozen_string_literal: true

class Api::GoalCreationChatController < Api::BaseController
  include SSEStreaming

  # GET /api/goal_creation_chat/stream
  # SSE stream for real-time message updates
  def stream
    stream_channel = "goal_creation_chat:#{current_user.id}"
    stream_from_channel(stream_channel)
  end

  # POST /api/goal_creation_chat/message
  # Stateless goal creation chat - processes user message and returns assistant response
  def message
    user_message = params[:message]&.strip
    conversation_history = params[:conversation_history] || []

    if user_message.blank?
      render json: { error: 'Message cannot be blank' }, status: :unprocessable_entity
      return
    end

    begin
      # Build conversation for LLM
      messages = build_conversation_messages(conversation_history, user_message)
      
      # Build user context for better suggestions
      user_context = build_user_context
      
      # Stream channel for this conversation (use user ID as unique identifier)
      stream_channel = "goal_creation_chat:#{current_user.id}"
      
      # Emit start event
      Streams::Broker.publish(stream_channel, event: :start, data: {})
      
      # Call LLM with streaming using Service.call
      accumulated_text = ""
      tool_call_emitted = false
      result = Llms::Service.call(
        system: Llms::Prompts::Goals.creation_chat_system_prompt(user_context: user_context),
        messages: messages,
        tools: [Llms::Prompts::Goals.creation_tool_definition],
        user: current_user,
        stream: true
      ) do |delta|
        # Handle different delta types
        if delta.is_a?(String)
          # Text streaming
          accumulated_text += delta
          Streams::Broker.publish(stream_channel, event: :chunk, data: { delta: delta })
        elsif delta.is_a?(Hash) && delta[:type] == 'tool_start'
          # Tool call detected during streaming - emit immediately!
          if delta[:tool_name] == 'finalize_goal_creation' && !tool_call_emitted
            Rails.logger.info("[GoalCreationChat] Tool call detected DURING stream: #{delta[:tool_name]}")
            Streams::Broker.publish(stream_channel, event: :tool_call, data: { tool: 'finalize_goal_creation' })
            tool_call_emitted = true
          end
        end
      end
      
      # Emit done event (tool_call already emitted during streaming if present)
      Streams::Broker.publish(stream_channel, event: :done, data: {})

      # Extract tool calls from result
      tool_calls = result[:tool_calls]

      # Check if LLM called the finalize tool (tool_call event already sent during stream)
      if tool_calls&.any? { |tc| tc[:name] == 'finalize_goal_creation' }
        tool_call = tool_calls.find { |tc| tc[:name] == 'finalize_goal_creation' }
        
        render json: {
          reply: accumulated_text.presence || "I have all the information I need!",
          ready_to_create: true,
          goal_data: tool_call[:parameters]
        }
      else
        # Continue conversation — ensure reply is never empty
        render json: {
          reply: accumulated_text.presence || "Could you tell me more about that?",
          ready_to_create: false
        }
      end
    rescue => e
      Rails.logger.error("[GoalCreationChat] Error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      render json: { error: 'Failed to process message. Please try again.' }, status: :internal_server_error
    end
  end

  private

  def build_conversation_messages(history, new_message)
    messages = []
    
    # Add conversation history
    history.each do |msg|
      messages << {
        role: msg['role'],
        content: [{ type: 'text', text: msg['content'] }]
      }
    end
    
    # Add new user message
    messages << {
      role: 'user',
      content: [{ type: 'text', text: new_message }]
    }
    
    messages
  end

  def build_user_context
    # Get user's existing goals (exclude archived)
    active_goals = current_user.goals.where.not(status: :archived).order(created_at: :desc).limit(10)
    
    existing_goals = active_goals.map do |goal|
      {
        title: goal.title,
        description: goal.description,
        status: goal.status
      }
    end

    # Get global learnings (from all active goals)
    learnings = active_goals.flat_map do |goal|
      goal.learnings || []
    end.uniq.take(20)

    {
      existing_goals: existing_goals,
      learnings: learnings,
      total_goals: current_user.goals.count
    }
  end
end
