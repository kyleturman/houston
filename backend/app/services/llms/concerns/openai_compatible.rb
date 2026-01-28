# frozen_string_literal: true

module Llms
  module Concerns
    # Shared functionality for OpenAI-compatible API adapters (OpenAI, OpenRouter, Ollama)
    #
    # This module extracts common patterns used across OpenAI-format APIs:
    # - Tool definition formatting
    # - Tool result formatting
    # - Response normalization
    # - Streaming buffer management
    #
    # Usage:
    #   class OpenAIAdapter < Base
    #     include Concerns::OpenAICompatible
    #   end
    #
    module OpenAICompatible
      # ============================================================================
      # TOOL DEFINITION FORMATTING
      # ============================================================================

      # Convert tool definitions to OpenAI function format
      # Input:  [{ name: String, description: String, input_schema: Hash }]
      # Output: [{ type: 'function', function: { name:, description:, parameters: } }]
      def format_tool_definitions_openai(tools)
        Array(tools).map do |tool|
          {
            type: 'function',
            function: {
              name: hash_get(tool, :name),
              description: hash_get(tool, :description),
              parameters: hash_get(tool, :input_schema) || {}
            }
          }
        end
      end

      # ============================================================================
      # TOOL RESULT FORMATTING
      # ============================================================================

      # Format tool results in unified content block format
      # Used by format_messages() to convert to provider-specific format
      def format_tool_results_openai(tool_results)
        tool_results.map do |tr|
          result = {
            'type' => 'tool_result',
            'tool_call_id' => tr[:call_id],
            'content' => tr[:result].to_s
          }
          result['is_error'] = tr[:is_error] if tr.key?(:is_error)
          result
        end
      end

      # ============================================================================
      # RESPONSE NORMALIZATION
      # ============================================================================

      # Normalize OpenAI-format response to unified content block format
      # Converts: { choices: [{ message: { content:, tool_calls: [...] } }] }
      # To:       [{ 'type' => 'text', 'text' => ... }, { 'type' => 'tool_use', ... }]
      #
      # @param response [Hash] OpenAI-format API response
      # @param message_path [Array<String>] Path to message object (default: choices/0/message)
      # @return [Array<Hash>, nil] Normalized content blocks or nil
      def normalize_openai_response_for_history(response, message_path: ['choices', 0, 'message'])
        return nil unless response.is_a?(Hash)

        message = response.dig(*message_path)
        return nil unless message.is_a?(Hash)

        content_text = message['content']
        tool_calls = message['tool_calls']

        blocks = []
        blocks << { 'type' => 'text', 'text' => content_text } if content_text.present?

        if tool_calls.is_a?(Array) && tool_calls.any?
          tool_calls.each do |tc|
            next unless tc.is_a?(Hash)

            parsed_input = parse_tool_arguments_safe(tc.dig('function', 'arguments'))
            next if parsed_input.nil?

            blocks << {
              'type' => 'tool_use',
              'id' => tc['id'] || SecureRandom.uuid,
              'name' => tc.dig('function', 'name'),
              'input' => parsed_input
            }
          end
        end

        blocks.empty? ? nil : blocks
      end

      # ============================================================================
      # STREAMING BUFFER MANAGEMENT
      # ============================================================================

      # Initialize a streaming tool call buffer entry
      # Returns a safely-constructed buffer hash
      def init_tool_call_buffer
        {
          'id' => nil,
          'function' => { 'name' => String.new, 'arguments' => String.new },
          '_emitted_start' => false
        }
      end

      # Safely accumulate a streaming tool call delta into the buffer
      #
      # @param buffer [Hash] The tool_calls_buffer hash
      # @param index [Integer] Tool call index from delta
      # @param tc_delta [Hash] The tool call delta from stream
      # @param block [Proc] Optional block to yield tool_start events
      # @return [Hash] The buffer entry (for chaining)
      def accumulate_tool_call_delta(buffer, index, tc_delta, &block)
        # Ensure buffer entry exists
        buffer[index] ||= init_tool_call_buffer
        entry = buffer[index]

        # Guard: ensure entry is properly structured
        return entry unless entry.is_a?(Hash) && entry['function'].is_a?(Hash)

        # Accumulate id (only set once, first wins)
        entry['id'] ||= tc_delta['id'] if tc_delta['id'].present?

        # Accumulate function name
        name = tc_delta.dig('function', 'name')
        if name.present?
          entry['function']['name'] = name

          # Emit tool_start event once
          if block_given? && !entry['_emitted_start']
            yield({
              type: 'tool_start',
              tool_name: name,
              tool_id: tc_delta['id'] || entry['id'] || "tool_#{index}"
            })
            entry['_emitted_start'] = true
          end
        end

        # Accumulate arguments (preserve whitespace)
        args = tc_delta.dig('function', 'arguments')
        entry['function']['arguments'] << args if args

        entry
      end

      # Finalize streaming tool calls and emit tool_complete events
      #
      # @param buffer [Hash] The tool_calls_buffer hash
      # @param block [Proc] Block to yield tool_complete events
      # @return [Array<Hash>] Clean tool calls array (without internal tracking)
      def finalize_tool_calls_buffer(buffer, &block)
        return [] unless buffer.is_a?(Hash) && buffer.any?

        clean_tool_calls = []

        buffer.each do |index, tc|
          next unless tc.is_a?(Hash) && tc['function'].is_a?(Hash)

          # Parse arguments safely
          args = parse_tool_arguments_safe(tc['function']['arguments'])
          next if args.nil?

          # Emit tool_complete event
          if block_given?
            yield({
              type: 'tool_complete',
              tool_name: tc['function']['name'],
              tool_id: tc['id'] || "tool_#{index}",
              tool_input: args
            })
          end

          # Build clean tool call (without internal tracking fields)
          clean_tool_calls << {
            'id' => tc['id'],
            'function' => {
              'name' => tc['function']['name'],
              'arguments' => tc['function']['arguments']
            }
          }
        end

        clean_tool_calls
      end

      # ============================================================================
      # MESSAGE FORMATTING
      # ============================================================================

      # Format messages for OpenAI-compatible APIs
      # Handles both regular messages and tool result content blocks
      def format_messages_openai(messages)
        Array(messages).flat_map do |m|
          role = (m[:role] || m['role']).to_s
          content = m[:content] || m['content']

          # Handle tool result content blocks
          if content.is_a?(Array) && content.first.is_a?(Hash) && content.first['type'] == 'tool_result'
            content.map do |tr|
              {
                role: 'tool',
                tool_call_id: tr['tool_call_id'],
                content: tr['content'].to_s
              }
            end
          elsif content.is_a?(Array) && content.any? { |c| c.is_a?(Hash) && c['type'] == 'tool_use' }
            # Assistant message with tool_use blocks (Anthropic format) → convert to OpenAI format
            text_parts = content.filter_map { |c| c['text'] if c['type'] == 'text' }
            tool_uses = content.select { |c| c['type'] == 'tool_use' }

            msg = { role: 'assistant' }
            msg[:content] = text_parts.join("\n") if text_parts.any?
            msg[:tool_calls] = tool_uses.map do |tu|
              {
                id: tu['id'],
                type: 'function',
                function: {
                  name: tu['name'],
                  arguments: (tu['input'] || {}).to_json
                }
              }
            end
            msg
          else
            # Normal message — ensure content is never empty (some providers reject it)
            text = if content.is_a?(Array)
                     content.filter_map { |c| c['text'] || c[:text] }.join("\n")
                   else
                     content.to_s
                   end
            text = '...' if text.blank?
            { role: role, content: text }
          end
        end
      end

      # ============================================================================
      # USAGE EXTRACTION
      # ============================================================================

      # Extract usage from OpenAI-format response
      # @param response [Hash] API response
      # @param include_cached [Boolean] Whether to extract cached_tokens (OpenAI-specific)
      # @return [Hash] Standardized usage hash
      def extract_openai_usage(response, include_cached: false)
        usage = response['usage'] || {}
        result = {
          input_tokens: usage['prompt_tokens'] || 0,
          output_tokens: usage['completion_tokens'] || 0
        }

        if include_cached
          result[:cached_tokens] = usage.dig('prompt_tokens_details', 'cached_tokens') || 0
        else
          result[:cached_tokens] = 0
        end

        result
      end

      # ============================================================================
      # HELPER METHODS
      # ============================================================================

      private

      # Safely get value from hash with symbol or string key
      def hash_get(hash, key)
        return nil unless hash.is_a?(Hash)
        hash[key] || hash[key.to_s]
      end

      # Safely parse JSON arguments, returning nil on failure
      def parse_tool_arguments_safe(args)
        return {} if args.nil? || args.empty?
        return args if args.is_a?(Hash)

        JSON.parse(args)
      rescue JSON::ParserError => e
        Rails.logger.error("[OpenAICompatible] Failed to parse tool arguments: #{e.message}")
        nil
      end
    end
  end
end
