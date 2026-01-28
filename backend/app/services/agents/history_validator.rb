# frozen_string_literal: true

module Agents
  # Validates and repairs LLM conversation history
  #
  # Detects and fixes common corruption patterns:
  # - Orphaned tool_use blocks (missing tool_result)
  # - Invalid message structure
  # - Role alternation violations
  #
  # Called before CoreLoop starts to ensure history is valid for the LLM API.
  #
  # Usage:
  #   validator = HistoryValidator.new(agentable)
  #   result = validator.validate_and_repair!
  #   # => { valid: true, repairs: [] }
  #   # => { valid: true, repairs: ['Added missing tool_result for toolu_123'] }
  #
  class HistoryValidator
    # Result of validation
    Result = Struct.new(:valid, :repairs, :errors, keyword_init: true) do
      def repaired?
        repairs&.any?
      end
    end

    def initialize(agentable)
      @agentable = agentable
      @repairs = []
      @errors = []
    end

    # Validates history and repairs if possible
    # Returns Result with validation status and any repairs made
    def validate_and_repair!
      history = @agentable.llm_history || []
      return Result.new(valid: true, repairs: [], errors: []) if history.empty?

      # Check for orphaned tool_use blocks
      repair_orphaned_tool_calls!(history)

      # Check for other structural issues
      validate_structure!(history)

      # If we made repairs, persist them
      if @repairs.any?
        @agentable.update_column(:llm_history, history)
        Rails.logger.warn("[HistoryValidator] Repaired history for #{@agentable.class.name}##{@agentable.id}: #{@repairs.join(', ')}")
      end

      Result.new(
        valid: @errors.empty?,
        repairs: @repairs,
        errors: @errors
      )
    end

    # Check if history is valid without repairing
    def valid?
      history = @agentable.llm_history || []
      return true if history.empty?

      orphaned = find_orphaned_tool_calls(history)
      orphaned.empty?
    end

    private

    # Find tool_use blocks that don't have a matching tool_result in the next user message
    def find_orphaned_tool_calls(history)
      orphaned = []

      history.each_with_index do |message, index|
        next unless message['role'] == 'assistant'

        tool_calls = extract_tool_calls(message)
        next if tool_calls.empty?

        # Look for tool_result in the next message(s)
        tool_results = find_tool_results_after(history, index)
        result_ids = tool_results.map { |tr| tr['tool_use_id'] }.compact

        # Find tool_use blocks without matching results
        tool_calls.each do |tc|
          call_id = tc['id']
          unless result_ids.include?(call_id)
            orphaned << {
              call_id: call_id,
              name: tc['name'],
              message_index: index
            }
          end
        end
      end

      orphaned
    end

    # Repair orphaned tool_use blocks by adding synthetic tool_result
    def repair_orphaned_tool_calls!(history)
      orphaned = find_orphaned_tool_calls(history)
      return if orphaned.empty?

      # Group orphaned calls by the message they appear in
      by_message = orphaned.group_by { |o| o[:message_index] }

      # For each message with orphaned calls, ensure there's a tool_result
      by_message.each do |message_index, calls|
        # Find or create the next user message for tool results
        next_user_index = find_next_user_message_index(history, message_index)

        synthetic_results = calls.map do |call|
          @repairs << "Added missing tool_result for #{call[:name]} (#{call[:call_id]})"

          {
            'type' => 'tool_result',
            'tool_use_id' => call[:call_id],
            'content' => "[System] Tool execution was interrupted. The operation may have partially completed. Please verify the current state before retrying.",
            'is_error' => true
          }
        end

        if next_user_index
          # Append to existing user message
          existing_content = history[next_user_index]['content']
          if existing_content.is_a?(Array)
            history[next_user_index]['content'] = existing_content + synthetic_results
          else
            # Convert string content to array with text block + tool results
            history[next_user_index]['content'] = [
              { 'type' => 'text', 'text' => existing_content.to_s }
            ] + synthetic_results
          end
        else
          # Insert new user message with tool results
          new_message = {
            'role' => 'user',
            'content' => synthetic_results
          }
          history.insert(message_index + 1, new_message)
        end
      end
    end

    # Extract tool_use blocks from an assistant message
    def extract_tool_calls(message)
      content = message['content']
      return [] unless content.is_a?(Array)

      content.select { |block| block['type'] == 'tool_use' }
    end

    # Find all tool_result blocks that appear after a given index
    def find_tool_results_after(history, start_index)
      results = []

      # Check subsequent messages (usually just the next one)
      ((start_index + 1)..[start_index + 2, history.length - 1].min).each do |i|
        message = history[i]
        next unless message && message['role'] == 'user'

        content = message['content']
        next unless content.is_a?(Array)

        results += content.select { |block| block['type'] == 'tool_result' }
      end

      results
    end

    # Find the index of the next user message after a given index
    def find_next_user_message_index(history, start_index)
      ((start_index + 1)...history.length).each do |i|
        return i if history[i]['role'] == 'user'
      end
      nil
    end

    # Validate overall history structure
    def validate_structure!(history)
      return if history.empty?

      # Check first message role (should typically be user for conversations)
      # But for agent-initiated tasks, assistant first is okay

      # Check for nil content
      history.each_with_index do |message, index|
        if message['content'].nil?
          @errors << "Message at index #{index} has nil content"
        end

        unless %w[user assistant].include?(message['role'])
          @errors << "Message at index #{index} has invalid role: #{message['role']}"
        end
      end

      # Check for excessive consecutive same-role messages (warning only)
      consecutive_count = 1
      last_role = nil

      history.each do |message|
        if message['role'] == last_role
          consecutive_count += 1
          if consecutive_count > 3
            Rails.logger.warn("[HistoryValidator] #{consecutive_count} consecutive #{last_role} messages detected")
          end
        else
          consecutive_count = 1
          last_role = message['role']
        end
      end
    end
  end
end
