# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require_relative '../concerns/openai_compatible'

module Llms
  module Adapters
    # OpenAI GPT adapter - minimal implementation
    class OpenAIAdapter < Base
      include Concerns::OpenAICompatible

      PROVIDER = :openai
      DEFAULT_MODEL = 'gpt-5'

      MODELS = {
        # GPT-5 Series (Released August 2025)
        'gpt-5' => {
          api_id: 'gpt-5',
          input_cost: 1.25,
          output_cost: 10.00,
          cache_read_cost: 0.125,  # 0.1x input cost (90% savings)
          max_tokens: 128_000,
          context_window: 400_000  # 272k input + 128k output
        },
        'gpt-5-mini' => {
          api_id: 'gpt-5-mini',
          input_cost: 0.25,
          output_cost: 2.00,
          cache_read_cost: 0.025,  # 0.1x input cost (90% savings)
          max_tokens: 128_000,
          context_window: 400_000
        },
        'gpt-5-nano' => {
          api_id: 'gpt-5-nano',
          input_cost: 0.05,
          output_cost: 0.40,
          cache_read_cost: 0.005,  # 0.1x input cost (90% savings)
          max_tokens: 128_000,
          context_window: 400_000
        },
        'gpt-5-pro' => {
          api_id: 'gpt-5-pro',
          input_cost: 1.25,
          output_cost: 10.00,
          cache_read_cost: 0.125,  # 0.1x input cost (90% savings)
          max_tokens: 128_000,
          context_window: 400_000
        },
        # GPT-4.1 Series (Released April 2025)
        'gpt-4.1' => {
          api_id: 'gpt-4.1',
          input_cost: 2.00,
          output_cost: 8.00,
          cache_read_cost: 0.50,  # 0.25x input cost (75% savings)
          max_tokens: 16_384,
          context_window: 1_000_000
        }
      }.freeze

      def initialize(api_key: nil, model: nil, base_url: 'https://api.openai.com', max_tokens: nil, temperature: nil)
        super(model: model)
        @api_key = api_key || ENV['OPENAI_API_KEY']
        @base_url = base_url
        @max_tokens = (max_tokens || @model_config[:max_tokens]).to_i
        @temperature = (temperature || ENV['OPENAI_TEMPERATURE'] || 0.7).to_f
      end

      # Override: Use shared OpenAI message formatting
      def format_messages(messages)
        format_messages_openai(messages)
      end

      # Override: Use shared OpenAI tool definition format
      def format_tool_definitions(tools)
        format_tool_definitions_openai(tools)
      end

      # Override: Extract tool calls from OpenAI response
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

      # ONE method to handle all API calls
      def make_request(messages:, system:, tools:, stream:, &block)
        formatted_messages = format_messages(messages)
        msgs = build_messages_with_system(formatted_messages, system)
        body = build_request_body(msgs, tools, stream)

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

      def build_request_body(messages, tools, stream)
        body = {
          model: api_model_id,
          messages: messages,
          stream: stream
        }

        # GPT-5 series has different parameter requirements
        if model_key.start_with?('gpt-5')
          body[:max_completion_tokens] = @max_tokens
          # GPT-5 only supports temperature=1 (default), so omit it
        else
          body[:max_tokens] = @max_tokens
          body[:temperature] = @temperature
        end

        body[:tools] = tools if tools&.any?
        body[:stream_options] = { include_usage: true } if stream

        body
      end

      def standard_request(body, with_tools)
        response = http_post_json(
          "#{@base_url}/v1/chat/completions",
          headers: auth_headers,
          body: body
        )

        if with_tools
          response['_usage'] = extract_openai_usage(response, include_cached: true)
          response
        else
          text = response.dig('choices', 0, 'message', 'content') || ''
          { text: text, usage: extract_openai_usage(response, include_cached: true) }
        end
      end

      def stream_request(body, with_tools, &block)
        buffer = String.new
        tool_calls_buffer = {}
        total_usage = { input: 0, output: 0, cached: 0 }

        http_post_stream(
          "#{@base_url}/v1/chat/completions",
          headers: auth_headers,
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
            total_usage[:cached] = json.dig('usage', 'prompt_tokens_details', 'cached_tokens') || 0
          end
        end
      end

      def build_stream_response(buffer, tool_calls_buffer, total_usage, with_tools, &block)
        usage = {
          input_tokens: total_usage[:input],
          output_tokens: total_usage[:output],
          cached_tokens: total_usage[:cached]
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

      def auth_headers
        { 'Authorization' => "Bearer #{@api_key}" }
      end

      # Make parse_tool_arguments_safe accessible (defined in OpenAICompatible)
      def parse_tool_arguments_safe(args)
        return {} if args.nil? || args.empty?
        return args if args.is_a?(Hash)
        JSON.parse(args)
      rescue JSON::ParserError => e
        Rails.logger.error("[OpenAI] Failed to parse tool arguments: #{e.message}")
        nil
      end
    end
  end
end
