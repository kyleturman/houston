# frozen_string_literal: true

module Tools
  module System
    # Base class for system tools (note/task/etc.) used by our orchestrators.
    # Provider tools (e.g., web search) can subclass separately under another namespace.
    class BaseTool
      attr_reader :user, :goal, :task, :agentable, :context

      def initialize(user:, goal: nil, task: nil, agentable:, activity_id: nil, context: nil)
        @user = user
        @goal = goal
        @task = task
        @agentable = agentable
        @activity_id = activity_id
        @context = context || {}
        @stream_channel = Streams::Channels.for_agentable(agentable: @agentable)
      end

      # Execute the tool. Subclasses must implement and return a Hash payload.
      # Example: { success: true, note_id: 123 }
      def execute(**_kwargs)
        raise NotImplementedError, 'Subclasses must implement execute'
      end

      # Wrapper for execute with error handling and normalized result.
      def safe_execute(**kwargs)
        result = execute(**kwargs)
        normalize_result(result)
      rescue => e
        # Sanitize error message - never include full stack traces in LLM context
        clean_error = e.message.to_s.truncate(200)
        { success: false, error: clean_error, error_class: e.class.name }
      end

      # Tool metadata for planning and orchestration
      def self.metadata
        {
          name: name.demodulize.underscore.gsub('_tool', ''),
          description: 'Base tool class',
          params_hint: 'No parameters',
          completion_signal: false, # Set to true for tools that should terminate the agent loop
          is_user_facing: true # Set to false for internal tools that shouldn't create ThreadMessages
          # TODO: Add MCP annotations when needed (audience, priority, destructive, etc.)
        }
      end

      # JSON Schema for tool parameters (Anthropic API format)
      # Subclasses should override this to define their parameter schema
      # Returns: Hash with { type: 'object', properties: {...}, required: [...], additionalProperties: false }
      def self.schema
        { type: 'object', properties: {}, required: [], additionalProperties: false }
      end

      # Instance-level access to class metadata
      def metadata
        self.class.metadata
      end

      # Instance-level access to class schema
      def schema
        self.class.schema
      end

      protected

      # Emit progress update for this tool by updating the ThreadMessage metadata.
      # This triggers ThreadMessage.after_update to stream a unified 'message' SSE.
      def emit_tool_progress(message, data: {})
        return unless @activity_id

        begin
          msg = find_tool_message_by_activity_id(@activity_id)
          return unless msg

          # Build updates hash
          updates = { status: 'in_progress' }
          updates[:progress_message] = message if message.present?

          # Update top-level and data fields together
          msg.update_tool_activity_data(data, updates)
        rescue => e
          Rails.logger.error("[BaseTool] Failed to persist progress: #{e.message}")
        end
      end

      # Emit completion update for this tool. We defer status=success/failure updates
      # to Tools::Registry#create_tool_thread_message/update_tool_thread_message.
      # Here we only persist any final data/message so the UI can see it immediately.
      def emit_tool_completion(message = nil, data: {})
        return unless @activity_id

        begin
          msg = find_tool_message_by_activity_id(@activity_id)
          return unless msg

          # Build updates hash
          updates = {}
          updates[:progress_message] = message if message.present?

          # Update top-level and data fields together
          msg.update_tool_activity_data(data, updates)
        rescue => e
          Rails.logger.error("[BaseTool] Failed to persist completion: #{e.message}")
        end
      end

      # Helper to return a successful tool result with optional additional data
      # Example: success(observation: "Task created", task_id: 123)
      def success(**kwargs)
        { success: true }.merge(kwargs)
      end

      # Helper to return a failed tool result with an error message
      # Example: error("Failed to create task: invalid parameters")
      def error(message)
        { success: false, error: message.to_s.truncate(200) }
      end


      private

      def find_tool_message_by_activity_id(activity_id)
        ThreadMessage.where(
          user: @user,
          agentable: @agentable,
          source: :agent,
          message_type: :tool
        ).where("metadata -> 'tool_activity' ->> 'id' = ?", activity_id).first
      end

      def normalize_result(result)
        return { success: false, error: 'nil result' } if result.nil?
        return result if result.is_a?(Hash) && result.key?(:success)
        { success: true, result: result }
      end
    end
  end
end
