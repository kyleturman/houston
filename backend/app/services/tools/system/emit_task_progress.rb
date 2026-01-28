# frozen_string_literal: true

module Tools
  module System
    # Lightweight tool for agents to update task activity status with contextual messages.
    #
    # This allows task agents to show users what they're working on in real-time with
    # specific, contextual messages (e.g., "Researching baby toys" instead of generic
    # "Searching the web").
    #
    # The message is stored in the tool_activity metadata and streamed to the iOS app
    # via SSE events, appearing in the CreateTaskTool cell with a shimmer animation.
    #
    # Usage:
    #   emit_task_progress(message: "Researching baby toys")
    #   # ... then do web searches, create notes, etc.
    #
    class EmitTaskProgress < BaseTool
      # Tool metadata for planning and orchestration
      def self.metadata
        super.merge(
          name: 'emit_task_progress',
          description: "Update task status with a brief activity message shown to the user (e.g., 'Researching baby toys', 'Compiling book ideas'). Use when starting a major phase of work.",
          params_hint: 'message (required, 2-4 words, specific and fun)',
          is_user_facing: false # Updates parent task ThreadMessage, doesn't create its own cell
        )
      end

      # JSON Schema for tool parameters
      def self.schema
        {
          type: 'object',
          properties: {
            message: {
              type: 'string',
              description: "Brief, contextual status message (2-4 words). Be specific and fun! Examples: 'Researching baby toys', 'Finding hiking trails', 'Compiling book ideas'"
            }
          },
          required: ['message'],
          additionalProperties: false
        }
      end

      def execute(message:)
        # Validate message length
        if message.blank?
          return error("Message cannot be empty")
        end

        if message.length > 50
          return error("Message too long (max 50 characters)")
        end

        # Update the parent create_task ThreadMessage with this activity message
        update_parent_task_message(message)

        # The message is automatically captured in tool_activity metadata
        # and streamed via tool_execution_start SSE event
        success(
          message: message,
          display_message: "Updated activity status: #{message}"
        )
      end

      private

      def update_parent_task_message(message)
        # Only works if this tool is being called by a task agent
        unless @task&.origin_tool_activity_id
          Rails.logger.warn("[EmitTaskProgress] No task or origin_tool_activity_id found")
          return
        end

        # Find the parent create_task ThreadMessage
        parent_message = ThreadMessage.where(
          user: @user,
          source: :agent,
          message_type: :tool,
          tool_activity_id: @task.origin_tool_activity_id
        ).first

        unless parent_message
          Rails.logger.warn("[EmitTaskProgress] No parent ThreadMessage found for tool_activity_id: #{@task.origin_tool_activity_id}")
          return
        end

        # Update the parent's display_message
        old_message = parent_message.metadata.dig('tool_activity', 'display_message')
        parent_message.update_tool_activity({ display_message: message })
        
        Rails.logger.info("[EmitTaskProgress] Updated parent ThreadMessage #{parent_message.id} display_message: '#{old_message}' → '#{message}'")
      rescue => e
        Rails.logger.error("[EmitTaskProgress] Failed to update parent task message: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
        # Don't fail the tool execution if we can't update the parent
      end
    end
  end
end
