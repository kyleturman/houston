# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require_relative '../concerns/openai_compatible'

module Llms
  module Adapters
    # Ollama local LLM adapter
    # Supports any model installed locally via Ollama
    #
    # Configuration:
    #   LLM_AGENTS_MODEL=ollama:llama3.3
    #   LLM_TASKS_MODEL=ollama:qwen2.5:72b
    #   OLLAMA_BASE_URL=http://localhost:11434 (optional, this is default)
    #   OLLAMA_API_KEY=optional (Ollama doesn't require auth by default)
    #
    # All costs are $0 since Ollama runs locally
    #
    class OllamaAdapter < Base
      include Concerns::OpenAICompatible

      PROVIDER = :ollama
      DEFAULT_MODEL = 'llama3.3'

      # Dynamic model support - any model installed in Ollama
      # All local models have zero cost
      # Note: We don't cache the result so ENV vars are read fresh each time (important for tests)
      MODELS = Hash.new do |_hash, key|
        {
          api_id: key,
          input_cost: 0.0,   # Local = free
          output_cost: 0.0,  # Local = free
          cache_read_cost: 0.0,
          max_tokens: ENV['OLLAMA_MAX_TOKENS']&.to_i || 4096,
          context_window: ENV['OLLAMA_CONTEXT_WINDOW']&.to_i || 128_000
        }
      end

      def initialize(api_key: nil, model: nil, base_url: nil, max_tokens: nil, temperature: nil)
        # Set model first so super() can find it in MODELS hash
        @model_key = model || DEFAULT_MODEL
        super(model: @model_key)

        @api_key = api_key || ENV['OLLAMA_API_KEY']  # Optional - Ollama doesn't require auth
        @base_url = base_url || ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
        @max_tokens = (max_tokens || @model_config[:max_tokens]).to_i
        @temperature = (temperature || ENV['OLLAMA_TEMPERATURE'] || 0.7).to_f
      end

      # Override: Ollama uses standard message format with special handling for content arrays
      def format_messages(messages)
        Array(messages).flat_map do |m|
          role = (m[:role] || m['role']).to_s
          content = m[:content] || m['content']

          # Handle tool result content blocks
          if content.is_a?(Array) && content.first.is_a?(Hash) && content.first['type'] == 'tool_result'
            # Ollama expects tool results as regular tool messages
            content.map do |tr|
              {
                role: 'tool',
                content: tr['content'].to_s
              }
            end
          elsif content.is_a?(Array)
            # Extract text from content blocks (Anthropic-style format)
            text_content = content.filter_map do |block|
              next unless block.is_a?(Hash)
              block[:text] || block['text']
            end.join("\n")

            { role: role, content: text_content }
          else
            # Normal message (already a string)
            { role: role, content: content.to_s }
          end
        end
      end

      # Override: Use shared OpenAI tool definition format
      def format_tool_definitions(tools)
        format_tool_definitions_openai(tools)
      end

      # Override: Extract tool calls from Ollama response
      # Handles OpenAI format (used by Llama, Qwen, Mistral, etc. via Ollama)
      def extract_tool_calls(response)
        # Ollama format: response.message.tool_calls
        message = response['message']
        return [] unless message.is_a?(Hash) && message['tool_calls'].is_a?(Array)

        message['tool_calls'].filter_map do |tc|
          next unless tc.is_a?(Hash)

          # Get arguments - handle both Hash and JSON string
          args = parse_tool_arguments_safe(tc.dig('function', 'arguments'))
          next if args.nil?

          # Ollama normalizes all models to OpenAI format
          standardize_tool_call(
            'id' => tc['id'] || SecureRandom.uuid,  # Generate ID if not provided
            'name' => tc.dig('function', 'name'),
            'arguments' => args
          )
        end
      end

      # Override: Use shared tool result formatting
      def format_tool_results(tool_results)
        format_tool_results_openai(tool_results)
      end

      # Override: Normalize Ollama response to unified content block format
      def normalize_response_for_history(response)
        return nil unless response.is_a?(Hash)

        message = response['message']
        return nil unless message.is_a?(Hash)

        content_text = message['content']
        tool_calls = message['tool_calls']

        blocks = []
        blocks << { 'type' => 'text', 'text' => content_text } if content_text.present?

        if tool_calls.is_a?(Array) && tool_calls.any?
          tool_calls.each do |tc|
            next unless tc.is_a?(Hash)

            args = tc.dig('function', 'arguments')
            # Ollama may return args as Hash already
            parsed_args = args.is_a?(Hash) ? args : (parse_tool_arguments_safe(args) || {})

            blocks << {
              'type' => 'tool_use',
              'id' => tc['id'] || SecureRandom.uuid,
              'name' => tc.dig('function', 'name'),
              'input' => parsed_args
            }
          end
        end

        blocks.empty? ? nil : blocks
      end

      # Main request handler
      def make_request(messages:, system:, tools:, stream:, &block)
        # Format messages to Ollama's expected format
        formatted_messages = format_messages(messages)
        msgs = build_messages_with_system(formatted_messages, system)

        body = {
          model: api_model_id,
          messages: msgs,
          stream: stream,
          options: {
            temperature: @temperature,
            num_predict: @max_tokens  # Ollama uses num_predict instead of max_tokens
          }
        }
        body[:tools] = tools if tools&.any?

        if stream && block_given?
          stream_request(body, tools.present?, &block)
        else
          standard_request(body, tools.present?)
        end
      end

      private

      def build_messages_with_system(messages, system)
        system.present? ? [{ role: 'system', content: system }] + messages : messages
      end

      def standard_request(body, with_tools)
        response = ollama_post_json('/api/chat', body: body)

        if with_tools
          usage = extract_ollama_usage(response)
          # Wrap in choices format for consistency with other adapters
          {
            'choices' => [{ 'message' => response['message'] }],
            'message' => response['message'],  # Keep original for extract_tool_calls
            '_usage' => usage
          }
        else
          text = response.dig('message', 'content') || ''
          { text: text, usage: extract_ollama_usage(response) }
        end
      end

      def stream_request(body, with_tools, &block)
        buffer = String.new
        tool_calls_buffer = {}
        total_usage = { input: 0, output: 0 }
        last_message = nil

        ollama_post_stream('/api/chat', body: body) do |chunk|
          process_stream_chunk(chunk, buffer, tool_calls_buffer, total_usage, with_tools, last_message, &block)
        end

        build_stream_response(buffer, tool_calls_buffer, total_usage, with_tools, &block)
      end

      def process_stream_chunk(chunk, buffer, tool_calls_buffer, total_usage, with_tools, last_message, &block)
        chunk.each_line do |line|
          line = line.strip
          next if line.empty?

          json = JSON.parse(line) rescue next
          message = json['message']

          # Accumulate text content (preserve whitespace)
          if message&.dig('content')
            delta = message['content']
            buffer << delta
            # Always yield text for streaming (callers need it even when tools are present)
            yield delta if block_given? && delta
          end

          # Extract tool calls (Ollama sends complete tool calls, not deltas)
          if with_tools && message&.dig('tool_calls').is_a?(Array)
            message['tool_calls'].each_with_index do |tc, index|
              next unless tc.is_a?(Hash)

              tool_id = tc['id'] || "tool_#{index}"

              # Only emit events if we haven't seen this tool yet
              unless tool_calls_buffer[tool_id]
                tool_calls_buffer[tool_id] = tc

                # Emit tool_start
                if block_given?
                  yield({
                    type: 'tool_start',
                    tool_name: tc.dig('function', 'name'),
                    tool_id: tool_id
                  })
                end
              end
            end
          end

          # Track usage from final message
          if json['done']
            total_usage[:input] = json['prompt_eval_count'] || 0
            total_usage[:output] = json['eval_count'] || 0
          end
        end
      end

      def build_stream_response(buffer, tool_calls_buffer, total_usage, with_tools, &block)
        # Emit tool_complete events
        if with_tools && tool_calls_buffer.any? && block_given?
          tool_calls_buffer.each do |tool_id, tc|
            next unless tc.is_a?(Hash)

            args = tc.dig('function', 'arguments')
            parsed_args = args.is_a?(Hash) ? args : (parse_tool_arguments_safe(args) || {})

            yield({
              type: 'tool_complete',
              tool_name: tc.dig('function', 'name'),
              tool_id: tool_id,
              tool_input: parsed_args
            })
          end
        end

        usage = {
          input_tokens: total_usage[:input],
          output_tokens: total_usage[:output],
          cached_tokens: 0
        }

        if with_tools && tool_calls_buffer.any?
          {
            'choices' => [{
              'message' => {
                'role' => 'assistant',
                'content' => buffer.present? ? buffer : nil,
                'tool_calls' => tool_calls_buffer.values
              }
            }],
            'message' => {
              'role' => 'assistant',
              'content' => buffer.present? ? buffer : nil,
              'tool_calls' => tool_calls_buffer.values
            },
            '_usage' => usage
          }
        elsif with_tools
          { 'content' => [{ 'type' => 'text', 'text' => buffer }], '_usage' => usage }
        else
          { text: buffer, usage: usage }
        end
      end

      def extract_ollama_usage(response)
        {
          input_tokens: response['prompt_eval_count'] || 0,
          output_tokens: response['eval_count'] || 0,
          cached_tokens: 0
        }
      end

      # Ollama-specific HTTP methods (no authentication by default)
      def ollama_post_json(path, body:)
        uri = URI.parse("#{@base_url}#{path}")
        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/json'
        req['Authorization'] = "Bearer #{@api_key}" if @api_key.present?
        req.body = JSON.dump(body)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 300  # 5 minutes for large models

        res = http.request(req)
        unless res.is_a?(Net::HTTPSuccess)
          error_body = res.body.to_s
          Rails.logger.error("[Ollama] #{res.code} error: #{error_body[0..500]}")
          raise "Ollama API error: #{res.code} - #{error_body[0..200]}"
        end

        JSON.parse(res.body)
      end

      def ollama_post_stream(path, body:, &block)
        uri = URI.parse("#{@base_url}#{path}")
        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/json'
        req['Authorization'] = "Bearer #{@api_key}" if @api_key.present?
        req.body = JSON.dump(body)

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 300) do |http|
          http.request(req) do |response|
            unless response.is_a?(Net::HTTPSuccess)
              error_body = response.body.to_s
              Rails.logger.error("[Ollama Streaming] #{response.code} error: #{error_body[0..500]}")
              raise "Ollama API error: #{response.code} - #{error_body[0..200]}"
            end

            response.read_body do |chunk|
              yield chunk if block_given?
            end
          end
        end
      end

      # Make parse_tool_arguments_safe accessible
      def parse_tool_arguments_safe(args)
        return {} if args.nil?
        return {} if args.is_a?(String) && args.empty?
        return args if args.is_a?(Hash)
        JSON.parse(args)
      rescue JSON::ParserError => e
        Rails.logger.error("[Ollama] Failed to parse tool arguments: #{e.message}")
        nil
      end
    end
  end
end
