# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Llms
  module Adapters
    # Anthropic Claude adapter - minimal implementation
    class AnthropicAdapter < Base
      PROVIDER = :anthropic
      DEFAULT_MODEL = 'sonnet-4.5'
      
      MODELS = {
        'sonnet-4.5' => {
          api_id: 'claude-sonnet-4-5',
          input_cost: 3.00,
          output_cost: 15.00,
          cache_write_cost: 3.75,  # 1.25x input cost
          cache_read_cost: 0.30,   # 0.1x input cost (90% savings)
          max_tokens: 8192,
          context_window: 200_000,
          min_cacheable_tokens: 1024
        },
        'haiku-4.5' => {
          api_id: 'claude-haiku-4-5',
          input_cost: 1.00,
          output_cost: 5.00,
          cache_write_cost: 1.25,  # 1.25x input cost
          cache_read_cost: 0.10,   # 0.1x input cost (90% savings)
          max_tokens: 8192,
          context_window: 200_000,
          min_cacheable_tokens: 4096
        },
        'haiku-3.5' => {
          api_id: 'claude-3-5-haiku-20241022',
          input_cost: 0.80,
          output_cost: 4.00,
          cache_write_cost: 1.00,    # 1.25x input cost
          cache_read_cost: 0.08,     # 0.1x input cost (90% savings)
          max_tokens: 8192,
          context_window: 200_000,
          min_cacheable_tokens: 1024
        }
      }.freeze

      def initialize(api_key: nil, model: nil, base_url: 'https://api.anthropic.com', version: '2023-06-01', max_tokens: nil, temperature: nil)
        super(model: model)
        @api_key = api_key || ENV['ANTHROPIC_API_KEY']
        @base_url = base_url
        @version = version
        @max_tokens = (max_tokens || @model_config[:max_tokens]).to_i
        @temperature = (temperature || ENV['ANTHROPIC_TEMPERATURE'] || 0.2).to_f
      end

      # Override: Anthropic uses array format for content
      def format_messages(messages)
        Array(messages).filter_map do |m|
          content = m[:content] || m['content']
          next if content.nil?

          role = m[:role] || m['role']
          next if role.nil?

          # Preserve content type - Anthropic accepts both String and Array
          { role: role.to_s, content: content }
        end
      end

      # Override: Convert tool definitions to Anthropic format
      def format_tool_definitions(tools)
        Array(tools).map do |tool|
          {
            name: tool[:name] || tool['name'],
            description: tool[:description] || tool['description'],
            input_schema: tool[:input_schema] || tool['input_schema'] || {}
          }
        end
      end

      # Override: Format tool results for Anthropic
      # Converts tool results back to Anthropic format for next LLM call
      def format_tool_results(tool_results)
        tool_results.map do |tr|
          result = {
            type: 'tool_result',
            tool_use_id: tr[:call_id],
            content: tr[:result].to_s
          }
          # Include is_error if present (tells Claude whether tool execution succeeded)
          # is_error: true signals an error, is_error: false/nil signals success
          result[:is_error] = tr[:is_error] if tr.key?(:is_error)
          result
        end
      end

      # Override: Extract tool calls from Anthropic response
      def extract_tool_calls(response)
        return [] unless response.is_a?(Hash)

        content = response['content'] || []
        content.filter_map do |block|
          next unless block&.dig('type') == 'tool_use'

          # Check if this tool_use block has a parse error from streaming
          if block['_parse_error']
            # Return a special error tool call that CoreLoop will handle
            # This allows Claude to see the error and retry with corrections
            {
              name: block['name'],
              call_id: block['id'],
              parameters: {},
              _parse_error: block['_parse_error']
            }
          else
            # Normal tool call - use base adapter's standardize_tool_call
            standardize_tool_call(block)
          end
        end
      end

      # Override: Normalize Anthropic response for history storage
      # Filters out empty text blocks and removes internal error flags
      def normalize_response_for_history(response)
        return response unless response.is_a?(Hash) && response['content'].is_a?(Array)

        # Filter out empty text blocks (Anthropic streaming bug workaround)
        # Also remove internal _parse_error flags before storing in history
        filtered_content = response['content'].reject do |block|
          block.is_a?(Hash) && block['type'] == 'text' && block['text'].to_s.strip.empty?
        end.map do |block|
          # Remove internal error tracking fields before persisting
          if block.is_a?(Hash) && block['_parse_error']
            block = block.dup
            block.delete('_parse_error')
          end
          block
        end

        # Return filtered array, or nil if empty
        filtered_content.empty? ? nil : filtered_content
      end

      # ONE method to handle all API calls
      def make_request(messages:, system:, tools:, stream:, &block)
        body = build_request_body(messages, system, tools, stream)
        has_tools = tools.is_a?(Array) && tools.any?
        
        if stream && block_given?
          stream_request(body, has_tools, &block)
        else
          standard_request(body, has_tools)
        end
      end

      private

      def build_request_body(messages, system, tools, stream)
        # Format and filter messages first (removes nil role/content)
        formatted_messages = format_messages(messages)

        # Validate messages before sending to API
        if formatted_messages.empty?
          Rails.logger.error("[Anthropic] No valid messages after formatting! Original count: #{messages.length}")
          raise "No valid messages to send to API - all messages were filtered out"
        end

        # Check for malformed messages
        malformed = formatted_messages.select { |m| m[:role].nil? || m[:content].nil? }
        if malformed.any?
          Rails.logger.error("[Anthropic] Found #{malformed.length} malformed messages after formatting!")
          Rails.logger.error("[Anthropic] Malformed messages: #{malformed.inspect}")
          raise "Malformed messages detected: #{malformed.length} messages have nil role or content"
        end

        # Apply caching to system prompt if long enough
        system_content = if system.present? && should_cache_system?(system)
          # System can be string or array - convert to array format with cache_control
          [{
            type: 'text',
            text: system.to_s,
            cache_control: { type: 'ephemeral' }
          }]
        else
          system.to_s.presence
        end

        # Apply caching to tools if present and long enough
        cached_tools = if tools.present? && should_cache_tools?(tools)
          # Mark the last tool for caching (cache breakpoint)
          tools_copy = tools.deep_dup
          tools_copy.last[:cache_control] = { type: 'ephemeral' }
          tools_copy
        else
          tools
        end

        body = {
          model: api_model_id,
          max_tokens: @max_tokens,
          temperature: @temperature,
          system: system_content,
          messages: formatted_messages,
          tools: cached_tools,
          stream: stream
        }.compact

        body
      end

      def standard_request(body, with_tools)
        url = File.join(@base_url, '/v1/messages')
        
        # DEBUG: Log request details for 400 errors
        Rails.logger.info("[Anthropic] Making request with #{body[:messages]&.length || 0} messages, system: #{body[:system].present?}, tools: #{body[:tools]&.length || 0}")
        
        begin
          response = http_post_json(url, headers: anthropic_headers, body: body)
        rescue => e
          # Log the full request body on error
          Rails.logger.error("[Anthropic] Request failed: #{e.message}")
          Rails.logger.error("[Anthropic] Request body: #{JSON.pretty_generate(body)}")
          raise
        end
        
        # Return raw response - CoreLoop and extract_tool_calls expect this format
        response['_usage'] = extract_usage(response)
        response
      end

      def stream_request(body, with_tools, &block)
        final_text = +''
        content_blocks = []
        tool_input_buffers = {} # Track partial JSON for each tool by index
        text_buffers = {} # Track accumulated text for each text block by index
        usage_data = {}

        url = File.join(@base_url, '/v1/messages')
        
        # DEBUG: Log request details for 400 errors
        Rails.logger.info("[Anthropic] Streaming request with #{body[:messages]&.length || 0} messages, system: #{body[:system].present?}, tools: #{body[:tools]&.length || 0}")
        
        begin
          # Line buffer for incomplete SSE lines across chunks
          # SSE events can span multiple TCP chunks, so we must buffer incomplete lines
          line_buffer = +''

          http_post_stream(url, headers: anthropic_headers(stream: true, with_tools: with_tools), body: body) do |chunk|
          parse_sse_events(chunk, line_buffer) do |event|
            case event['type']
            when 'content_block_start'
              # Initialize content block
              block_index = event['index']
              content_block = event['content_block']
              next unless block_index.is_a?(Integer) && content_block.is_a?(Hash)

              # Always store content blocks (text + tool_use)
              content_blocks[block_index] = content_block

              # Initialize buffers based on block type
              if content_block['type'] == 'tool_use'
                # Per Anthropic spec: content_block_start ALWAYS has input: {} (empty object)
                # The actual input arrives via input_json_delta events
                # We initialize buffer to accumulate these partial JSON strings
                tool_input_buffers[block_index] = +''

                # Yield tool start event for early detection
                if block_given?
                  yield({ type: 'tool_start', tool_name: content_block['name'], tool_id: content_block['id'] })
                end
              elsif content_block['type'] == 'text'
                text_buffers[block_index] = +''
              end

            when 'content_block_delta'
              block_index = event['index']
              next unless block_index.is_a?(Integer)

              delta = event['delta']
              next unless delta.is_a?(Hash)

              if delta['type'] == 'text_delta'
                # Text content
                # NOTE: Use `if text` not `if text.present?` to preserve whitespace-only chunks
                text = delta['text']
                final_text << text if text
                # Accumulate text into our buffer
                if text
                  # Ensure buffer exists for this block
                  text_buffers[block_index] ||= +''
                  text_buffers[block_index] << text
                end
                # Always yield text for streaming (Service.agent_call expects this)
                yield text if block_given? && text
              elsif delta['type'] == 'input_json_delta'
                # Tool input JSON chunk - accumulate it
                # NOTE: Use `if partial_json` not `if partial_json.present?` because
                # Rails' present? returns false for whitespace-only strings like " ",
                # which would drop space characters from the JSON stream causing
                # spacing issues like "After4Months" instead of "After 4 Months"
                partial_json = delta['partial_json']
                if partial_json
                  tool_input_buffers[block_index] ||= +''
                  tool_input_buffers[block_index] << partial_json

                  # Special handling for send_message tool - stream text parameter in real-time
                  tool_name = content_blocks[block_index]&.dig('name')
                  if tool_name == 'send_message' && block_given?
                    # Try to extract and stream text content as it arrives
                    yield({
                      type: 'send_message_chunk',
                      tool_id: content_blocks[block_index]['id'],
                      partial_json: partial_json
                    })
                  end
                end
              end

            when 'content_block_stop'
              block_index = event['index']
              next unless block_index.is_a?(Integer)

              content_block = content_blocks[block_index]

              # Guard against nil content_block (can happen if content_block_start event was missed)
              unless content_block
                Rails.logger.warn("[Anthropic] content_block_stop for index #{block_index} but no content_block exists - skipping finalization")
                next
              end

              # Finalize text blocks - set the accumulated text
              if text_buffers[block_index]
                content_block['text'] = text_buffers[block_index]
              end

              # Finalize tool input JSON
              # Check if buffer exists AND has content (not just empty string)
              if tool_input_buffers[block_index] && tool_input_buffers[block_index].present?
                begin
                  parsed_input = JSON.parse(tool_input_buffers[block_index])
                  content_block['input'] = parsed_input

                  # Yield tool_complete event for streaming handlers
                  if block_given? && content_block['type'] == 'tool_use'
                    yield({
                      type: 'tool_complete',
                      tool_name: content_block['name'],
                      tool_id: content_block['id'],
                      tool_input: parsed_input
                    })
                  end
                rescue JSON::ParserError => e
                  # JSON parsing failed - log detailed error info
                  Rails.logger.error("[Anthropic] Failed to parse tool input JSON for tool '#{content_block['name']}': #{e.message}")
                  Rails.logger.error("[Anthropic] Buffer content: #{tool_input_buffers[block_index].inspect}")
                  Rails.logger.error("[Anthropic] Buffer length: #{tool_input_buffers[block_index].length} bytes")

                  # Mark this block as having a parse error
                  # CoreLoop will detect this and send an error result back to Claude
                  content_block['_parse_error'] = {
                    error: e.message,
                    raw_json: tool_input_buffers[block_index]
                  }
                  # Set input to empty so the block structure is valid for Anthropic
                  content_block['input'] = {}
                end
              elsif tool_input_buffers[block_index]
                # Buffer exists but is empty - no input_json_delta events received
                # This is normal for tools with empty parameters {}
                # Per Anthropic spec: content_block_start has input: {}, and for truly empty params,
                # they may skip input_json_delta events as an optimization
                Rails.logger.debug("[Anthropic] Tool '#{content_block['name']}' has empty parameters (no input_json_delta events)")

                # Set input to empty object (the intended parameters)
                content_block['input'] = {}

                # Yield tool_complete for empty-param tools too
                if block_given? && content_block['type'] == 'tool_use'
                  yield({
                    type: 'tool_complete',
                    tool_name: content_block['name'],
                    tool_id: content_block['id'],
                    tool_input: {}
                  })
                end
              end
              
            when 'message_delta'
              usage_data.merge!(event['usage'] || {})
            when 'message_start'
              usage_data.merge!(event.dig('message', 'usage') || {})
            end
          end
          end
        rescue => e
          # Log the full request body on error
          Rails.logger.error("[Anthropic] Streaming request failed: #{e.message}")
          Rails.logger.error("[Anthropic] Request body: #{JSON.pretty_generate(body)}")
          raise
        end
        
        usage = {
          input_tokens: usage_data['input_tokens'] || 0,
          output_tokens: usage_data['output_tokens'] || 0,
          cache_creation_input_tokens: usage_data['cache_creation_input_tokens'] || 0,
          cache_read_input_tokens: usage_data['cache_read_input_tokens'] || 0
        }

        # ALWAYS return raw format with content array (consistent with standard_request)
        # CoreLoop and extract_tool_calls expect this format
        # Note: We keep tool_use blocks even if they have _parse_error
        # CoreLoop will detect the error flag and send error results back to Claude
        if with_tools && content_blocks.any?
          # Filter out nil entries (can happen if content_block_start events were missed)
          filtered_blocks = content_blocks.compact
          { 'content' => filtered_blocks, '_usage' => usage }
        else
          # No tools or no content blocks - return text as content array
          { 'content' => [{ 'type' => 'text', 'text' => final_text }], '_usage' => usage }
        end
      end

      def anthropic_headers(stream: false, with_tools: false)
        headers = {
          'x-api-key' => @api_key,
          'anthropic-version' => @version
        }
        headers['anthropic-beta'] = 'fine-grained-tool-streaming-2025-05-14' if stream && with_tools
        headers
      end
      
      # Parse SSE events from a chunk, handling incomplete lines across chunks
      # line_buffer is mutated to carry over incomplete lines to the next chunk
      def parse_sse_events(chunk, line_buffer, &block)
        # Prepend any leftover data from previous chunk
        data = line_buffer + chunk
        line_buffer.clear

        lines = data.split("\n", -1)  # -1 to preserve trailing empty string if ends with \n

        # If the chunk doesn't end with newline, last element is incomplete
        # Keep it in buffer for next chunk
        unless data.end_with?("\n")
          line_buffer << lines.pop.to_s
        end

        lines.each do |line|
          line = line.strip
          next unless line.start_with?('data: ')

          event_data = line[6..-1].strip
          next if event_data.empty?

          begin
            event = JSON.parse(event_data)
            yield event if block_given?
          rescue JSON::ParserError => e
            # Log parse error for debugging
            Rails.logger.warn("[Anthropic SSE] JSON parse error: #{e.message}, data: #{event_data[0..100]}")
          end
        end
      end

      def extract_usage(response)
        usage = response['usage'] || {}
        {
          input_tokens: usage['input_tokens'] || 0,
          output_tokens: usage['output_tokens'] || 0,
          cache_creation_input_tokens: usage['cache_creation_input_tokens'] || 0,
          cache_read_input_tokens: usage['cache_read_input_tokens'] || 0
        }
      end

      # Determine if system prompt is long enough to cache
      # Min: 1024 tokens for Sonnet, 4096 for Haiku 4.5
      def should_cache_system?(system)
        return false unless system.present?

        # Rough estimate: 1 token ≈ 4 characters
        char_count = system.to_s.length
        min_tokens = @model_config[:min_cacheable_tokens]

        char_count >= (min_tokens * 4)
      end

      # Determine if tools are worth caching
      # Cache if we have multiple tools or tool definitions are substantial
      def should_cache_tools?(tools)
        return false unless tools.is_a?(Array) && tools.any?

        # Estimate total size of tool definitions
        total_chars = tools.sum { |t| t.to_json.length }
        min_tokens = @model_config[:min_cacheable_tokens]

        # Cache if tools would be at least min cacheable tokens
        total_chars >= (min_tokens * 4)
      end
    end
  end
end
