# frozen_string_literal: true

module Tools
  # Encapsulates selection and filtering policies for tool usage within a single LLM turn.
  # - Surfaces at most one tool cell (prefer a non-send_message tool)
  # - Executes at most MAX_ACTION_TOOLS non-send_message action tools plus one send_message (order preserved)
  #
  # Limiting parallel tools:
  # - Reduces SSE streaming buffer pressure (fewer concurrent JSON streams)
  # - Reduces cost (fewer parallel API calls)
  # - Encourages focused, sequential work over scattered parallel searches
  class Policy
    MAX_ACTION_TOOLS = 2  # Max non-send_message tools per turn

    attr_reader :selected_tool_id

    def initialize
      @selected_tool_id = nil
    end

    # Decide whether to surface a tool_start event as a UI cell.
    # Prefer a non-send_message tool; never surface send_message as a cell.
    # Returns true if the caller should create/update the tool cell for this tool.
    def consider_tool_start(tool_name, tool_id)
      return false if tool_name.to_s == 'send_message'
      if @selected_tool_id.nil?
        @selected_tool_id = tool_id
        return true
      end
      tool_id == @selected_tool_id
    end

    # Decide whether to update the surfaced tool cell on tool_complete.
    # If none has been selected yet and this is a non-send_message tool, select it now.
    # Returns true if the caller should apply the update for this tool.
    def consider_tool_complete(tool_name, tool_id)
      if @selected_tool_id.nil? && tool_name.to_s != 'send_message'
        @selected_tool_id = tool_id
      end
      tool_id == @selected_tool_id
    end

    # Filter tool calls for execution: keep at most MAX_ACTION_TOOLS non-send_message and one send_message, preserving order.
    # Expects an array of standardized tool calls: { name:, parameters:, call_id: }
    def filter_for_execution(tool_calls)
      return [] unless tool_calls.is_a?(Array)

      action_count = 0
      saw_send = false
      filtered = []

      tool_calls.each do |tc|
        name = tc[:name]
        next unless name.is_a?(String)

        if name == 'send_message'
          next if saw_send
          filtered << tc
          saw_send = true
        else
          next if action_count >= MAX_ACTION_TOOLS
          filtered << tc
          action_count += 1
        end
      end

      filtered
    end
  end
end
