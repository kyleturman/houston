# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require_relative '../concerns/openai_compatible'

module Llms
  module Adapters
    # OpenRouter API adapter
    # Provides access to 400+ models from multiple providers through one API
    #
    # Configuration:
    #   OPENROUTER_API_KEY=sk-or-...
    #   LLM_AGENTS_MODEL=openrouter:anthropic/claude-3-opus
    #   LLM_TASKS_MODEL=openrouter:meta-llama/llama-3.3-70b-instruct
    #
    # Optional cost tracking (defaults to $0):
    #   OPENROUTER_INPUT_COST=0.60   # per 1M tokens
    #   OPENROUTER_OUTPUT_COST=0.60  # per 1M tokens
    #
    # Popular models:
    #   anthropic/claude-3-opus, anthropic/claude-3-sonnet
    #   meta-llama/llama-3.3-70b-instruct
    #   openai/gpt-4-turbo, openai/gpt-4o
    #   google/gemini-pro-1.5
    #
    class OpenrouterAdapter < Base
      include Concerns::OpenAICompatible

      PROVIDER = :openrouter
      DEFAULT_MODEL = 'meta-llama/llama-3.3-70b-instruct'

      # Dynamic model support - any model available on OpenRouter
      # Note: We don't cache the result so ENV vars are read fresh each time (important for tests)
      MODELS = Hash.new do |_hash, key|
        {
          api_id: key,
          input_cost: ENV['OPENROUTER_INPUT_COST']&.to_f || 0.0,
          output_cost: ENV['OPENROUTER_OUTPUT_COST']&.to_f || 0.0,
          cache_read_cost: 0.0,  # OpenRouter doesn't expose caching details
          max_tokens: ENV['OPENROUTER_MAX_TOKENS']&.to_i || 4096,
          context_window: ENV['OPENROUTER_CONTEXT_WINDOW']&.to_i || 128_000
        }
      end

      def initialize(api_key: nil, model: nil, base_url: 'https://openrouter.ai/api/v1', max_tokens: nil, temperature: nil)
        # Set model first so super() can find it in MODELS hash
        @model_key = model || DEFAULT_MODEL
        super(model: @model_key)

        @api_key = api_key || ENV['OPENROUTER_API_KEY']
        @base_url = base_url
        @max_tokens = (max_tokens || @model_config[:max_tokens]).to_i
        @temperature = (temperature || ENV['OPENROUTER_TEMPERATURE'] || 0.7).to_f
        @app_name = ENV['OPENROUTER_APP_NAME'] || 'Houston'
        @site_url = ENV['OPENROUTER_SITE_URL'] || 'https://github.com/kyleturman/houston'
      end

      # Override: Use shared OpenAI message formatting
      def format_messages(messages)
        format_messages_openai(messages)
      end

      # Override: Use shared OpenAI tool definition format
      def format_tool_definitions(tools)
        format_tool_definitions_openai(tools)
      end

      # Override: Extract tool calls from OpenRouter response (OpenAI-compatible)
      def extract_tool_calls(response)
        message = response.dig('choices', 0, 'message')
        return [] unless message.is_a?(Hash) && message['tool_calls'].is_a?(Array)

        message['tool_calls'].filter_map do |tc|
          next unless tc.is_a?(Hash)

          args = parse_tool_arguments_safe(tc.dig('function', 'arguments'))
          next if args.nil?

          standardize_tool_call(
            'id' => tc['id'],
            'name' => tc.dig('function', 'name'),
            'arguments' => args
          )
        end
      end

      # Override: Use shared tool result formatting
      def format_tool_results(tool_results)
        format_tool_results_openai(tool_results)
      end

      # Override: Use shared response normalization
      def normalize_response_for_history(response)
        normalize_openai_response_for_history(response)
      end

      # Main request handler
      def make_request(messages:, system:, tools:, stream:, &block)
        formatted_messages = format_messages(messages)
        msgs = build_messages_with_system(formatted_messages, system)

        body = {
          model: api_model_id,
          messages: msgs,
          max_tokens: @max_tokens,
          temperature: @temperature,
          stream: stream
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

      def openrouter_headers
        headers = { 'Authorization' => "Bearer #{@api_key}" }
        headers['HTTP-Referer'] = @site_url if @site_url
        headers['X-Title'] = @app_name if @app_name
        headers
      end

      def standard_request(body, with_tools)
        response = http_post_json(
          "#{@base_url}/chat/completions",
          headers: openrouter_headers,
          body: body
        )

        if with_tools
          response['_usage'] = extract_openai_usage(response)
          response
        else
          text = response.dig('choices', 0, 'message', 'content') || ''
          { text: text, usage: extract_openai_usage(response) }
        end
      end

      def stream_request(body, with_tools, &block)
        buffer = String.new
        tool_calls_buffer = {}
        total_usage = { input: 0, output: 0 }

        http_post_stream(
          "#{@base_url}/chat/completions",
          headers: openrouter_headers,
          body: body
        ) do |chunk|
          process_stream_chunk(chunk, buffer, tool_calls_buffer, total_usage, with_tools, &block)
        end

        build_stream_response(buffer, tool_calls_buffer, total_usage, with_tools, &block)
      end

      def process_stream_chunk(chunk, buffer, tool_calls_buffer, total_usage, with_tools, &block)
        chunk.each_line do |line|
          next unless line.start_with?('data: ')

          data = line[6..-1].strip
          next if data == '[DONE]'

          json = JSON.parse(data) rescue next
          delta = json.dig('choices', 0, 'delta')

          # Accumulate text content
          if delta&.dig('content')
            text = delta['content']
            buffer << text
            # Always yield text for streaming (callers need it even when tools are present)
            yield text if block_given?
          end

          # Accumulate tool calls using shared helper
          if with_tools && delta&.dig('tool_calls')
            delta['tool_calls'].each do |tc_delta|
              next unless tc_delta.is_a?(Hash) && tc_delta['index']
              accumulate_tool_call_delta(tool_calls_buffer, tc_delta['index'], tc_delta, &block)
            end
          end

          # Extract usage from final chunk
          if json['usage']
            total_usage[:input] = json.dig('usage', 'prompt_tokens') || 0
            total_usage[:output] = json.dig('usage', 'completion_tokens') || 0
          end
        end
      end

      def build_stream_response(buffer, tool_calls_buffer, total_usage, with_tools, &block)
        usage = {
          input_tokens: total_usage[:input],
          output_tokens: total_usage[:output],
          cached_tokens: 0
        }

        if with_tools && tool_calls_buffer.any?
          clean_tool_calls = finalize_tool_calls_buffer(tool_calls_buffer, &block)

          {
            'choices' => [{
              'message' => {
                'role' => 'assistant',
                'content' => buffer.present? ? buffer : nil,
                'tool_calls' => clean_tool_calls
              }
            }],
            '_usage' => usage
          }
        elsif with_tools
          { 'content' => [{ 'type' => 'text', 'text' => buffer }], '_usage' => usage }
        else
          { text: buffer, usage: usage }
        end
      end

      # Make parse_tool_arguments_safe accessible (defined in OpenAICompatible)
      def parse_tool_arguments_safe(args)
        return {} if args.nil? || args.empty?
        return args if args.is_a?(Hash)
        JSON.parse(args)
      rescue JSON::ParserError => e
        Rails.logger.error("[OpenRouter] Failed to parse tool arguments: #{e.message}")
        nil
      end
    end
  end
end
