# frozen_string_literal: true

require_relative '../concerns/cost_tracking'

module Llms
  module Adapters
    # Base class for LLM adapters with built-in cost tracking
    #
    # == Creating a New Adapter ==
    #
    # REQUIRED:
    #   - Define PROVIDER constant (e.g., :anthropic)
    #   - Define DEFAULT_MODEL constant
    #   - Define MODELS hash with model configs
    #   - Implement make_request(messages:, system:, tools:, stream:, &block)
    #   - Override format_tool_definitions(tools) - convert tool definitions to provider format
    #   - Override extract_tool_calls(response) - extract tool calls from response
    #   - Override format_tool_results(tool_results) - format results for provider
    #
    # TOOL SUPPORT:
    #   This app requires tool/function calling. All adapters MUST implement
    #   the three tool methods above. They work together as a cycle:
    #     1. Send tools → LLM (format_tool_definitions)
    #     2. LLM responds with tool calls (extract_tool_calls)
    #     3. Send tool results → LLM (format_tool_results)
    #
    # EXAMPLES:
    #   See anthropic_adapter.rb or openai_adapter.rb
    #
    class Base
      include Concerns::CostTracking

      attr_reader :model_key, :model_config

      def initialize(model: nil, **opts)
        @model_key = model || self.class::DEFAULT_MODEL
        @model_config = self.class::MODELS[@model_key] || self.class::MODELS[self.class::DEFAULT_MODEL]
        raise "Unknown model: #{@model_key}" unless @model_config

        # Validate tool support implementation at initialization
        validate_tool_implementation!
      end

      # Subclasses must define PROVIDER constant
      def provider
        self.class::PROVIDER
      end

      # API model ID from config
      def api_model_id
        @model_config[:api_id]
      end

      # Generic cost calculation - accounts for caching
      # Anthropic: cache_creation_input_tokens, cache_read_input_tokens
      # OpenAI: cached_tokens
      def calculate_cost(input_tokens:, output_tokens:, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, cached_tokens: 0)
        input_cost = 0.0
        output_cost = (output_tokens.to_f / 1_000_000) * @model_config[:output_cost]

        # Handle Anthropic caching (cache_creation and cache_read)
        if cache_creation_input_tokens > 0 || cache_read_input_tokens > 0
          # Anthropic format
          # Regular input tokens (not cached)
          regular_input_tokens = input_tokens - cache_creation_input_tokens - cache_read_input_tokens
          input_cost += (regular_input_tokens.to_f / 1_000_000) * @model_config[:input_cost] if regular_input_tokens > 0

          # Cache write tokens (1.25x base cost)
          if cache_creation_input_tokens > 0 && @model_config[:cache_write_cost]
            input_cost += (cache_creation_input_tokens.to_f / 1_000_000) * @model_config[:cache_write_cost]
          end

          # Cache read tokens (0.1x base cost, 90% savings)
          if cache_read_input_tokens > 0 && @model_config[:cache_read_cost]
            input_cost += (cache_read_input_tokens.to_f / 1_000_000) * @model_config[:cache_read_cost]
          end
        # Handle OpenAI caching (cached_tokens)
        elsif cached_tokens > 0
          # OpenAI format
          # Regular input tokens (not cached)
          regular_input_tokens = input_tokens - cached_tokens
          input_cost += (regular_input_tokens.to_f / 1_000_000) * @model_config[:input_cost] if regular_input_tokens > 0

          # Cached tokens (0.5x base cost, 50% savings)
          if @model_config[:cache_read_cost]
            input_cost += (cached_tokens.to_f / 1_000_000) * @model_config[:cache_read_cost]
          end
        else
          # No caching - standard cost
          input_cost = (input_tokens.to_f / 1_000_000) * @model_config[:input_cost]
        end

        input_cost + output_cost
      end

      # Unified interface - subclasses just implement make_request
      def call(messages:, system: nil, tools: nil, stream: false, &block)
        # Convert to provider format
        formatted_messages = format_messages(messages)
        formatted_tools = tools ? format_tool_definitions(tools) : nil

        # Make the API request
        result = make_request(
          messages: formatted_messages,
          system: system,
          tools: formatted_tools,
          stream: stream,
          &block
        )

        # Track costs and return
        extract_and_track_usage(result)
      end

      # Subclasses implement this ONE method
      def make_request(messages:, system:, tools:, stream:, &block)
        raise NotImplementedError, "#{self.class} must implement make_request"
      end

      # Override if provider has different message format
      def format_messages(messages)
        messages
      end

      # ============================================================================
      # TOOL SUPPORT INTERFACE - REQUIRED FOR ALL ADAPTERS
      # ============================================================================
      # The tool calling cycle (all 3 methods work together):
      #
      #   1. format_tool_definitions → Prepare tool definitions to send TO provider
      #   2. extract_tool_calls    → Parse tool calls FROM provider response
      #   3. format_tool_results   → Prepare results to send TO provider
      #
      # Flow: We send tools → LLM picks tools → We execute → Send results → repeat
      # See anthropic_adapter.rb or openai_adapter.rb for complete examples.
      # ============================================================================

      # STEP 1: Convert our tools → provider format (sent TO the LLM)
      # Input:  [{ name: String, description: String, input_schema: Hash }]
      # Output: Provider's tool format (e.g., Anthropic's flat, OpenAI's nested)
      # Called by: CoreLoop before making LLM request
      def format_tool_definitions(tools)
        raise NotImplementedError, "#{self.class} must implement format_tool_definitions for tool support"
      end

      # STEP 2: Extract tool calls FROM provider response (LLM tells us what to run)
      # Input:  Provider's response hash
      # Output: [{ call_id: String, name: String, parameters: Hash }]
      # Called by: CoreLoop after receiving LLM response
      # Tip: Use standardize_tool_call() helper to handle key variations
      def extract_tool_calls(response)
        raise NotImplementedError, "#{self.class} must implement extract_tool_calls for tool support"
      end

      # STEP 3: Convert our results → provider format (sent TO the LLM)
      # Input:  [{ call_id: String, name: String, result: String, is_error: Boolean }]
      # Output: Provider's tool result format (e.g., Anthropic's tool_result, OpenAI's role='tool')
      # Called by: CoreLoop after executing tools
      # IMPORTANT: Must include is_error field to inform LLM of tool execution success/failure
      # Tip: Use standardize_tool_result() helper to ensure consistent formatting
      def format_tool_results(tool_results)
        raise NotImplementedError, "#{self.class} must implement format_tool_results for tool support"
      end

      # Normalize response content for LLM history storage
      #
      # ALL ADAPTERS MUST RETURN CONSISTENT FORMAT:
      #   - Array of content blocks: [{ 'type' => 'text'/'tool_use', ... }]
      #   - OR nil (if response is empty)
      #
      # Content block formats:
      #   Text: { 'type' => 'text', 'text' => '...' }
      #   Tool: { 'type' => 'tool_use', 'id' => '...', 'name' => '...', 'input' => {...} }
      #
      # This ensures CoreLoop and Service.rb remain provider-agnostic.
      # Each adapter converts its provider's native format to this standard.
      #
      # @param response [Hash] Raw provider response
      # @return [Array<Hash>, nil] Normalized content blocks or nil
      def normalize_response_for_history(response)
        # Default implementation - subclasses MUST override for proper normalization
        Rails.logger.warn("[#{self.class}] Using default normalize_response_for_history - adapter should override this!")
        response
      end

      protected

      # Validates that tool support is properly implemented
      # Checks if adapter implements tool methods consistently (all 3 or none)
      def validate_tool_implementation!
        # Check which tool methods are overridden
        has_format_tools = self.class.instance_method(:format_tool_definitions).owner != Base
        has_extract = self.class.instance_method(:extract_tool_calls).owner != Base
        has_format_results = self.class.instance_method(:format_tool_results).owner != Base

        # Count how many are implemented
        implemented_count = [has_format_tools, has_extract, has_format_results].count(true)

        # Warn if only some are implemented (all 3 or none is OK)
        if implemented_count > 0 && implemented_count < 3
          missing = []
          missing << 'format_tool_definitions' unless has_format_tools
          missing << 'extract_tool_calls' unless has_extract
          missing << 'format_tool_results' unless has_format_results

          Rails.logger.warn(
            "[#{self.class}] Incomplete tool support! Missing: #{missing.join(', ')}. " \
            "For tool support, implement ALL THREE methods. See anthropic_adapter.rb for example."
          )
        end
      rescue => e
        # Don't crash initialization, just log
        Rails.logger.error("[#{self.class}] Tool validation error: #{e.message}")
      end

      # Helper: Standardize tool call format - handles string/symbol keys automatically
      # Converts any reasonable format to: { call_id:, name:, parameters: }
      # Accepts common variations: id->call_id, input->parameters, arguments->parameters
      def standardize_tool_call(tool_call)
        return nil unless tool_call.is_a?(Hash)

        # Use HashAccessor to handle both string and symbol keys
        name = Utils::HashAccessor.hash_get_string(tool_call, :name)
        return nil unless name.present?

        # Try 'parameters' first, fall back to common alternatives
        params = Utils::HashAccessor.hash_get_hash(tool_call, :parameters) ||
                 Utils::HashAccessor.hash_get_hash(tool_call, :arguments) ||
                 Utils::HashAccessor.hash_get_hash(tool_call, :input) ||
                 {}

        # Try 'call_id' first, fall back to 'id'
        call_id = Utils::HashAccessor.hash_get_string(tool_call, :call_id) ||
                  Utils::HashAccessor.hash_get_string(tool_call, :id)
        return nil unless call_id.present?

        {
          name: name,
          parameters: params,
          call_id: call_id
        }
      rescue => e
        Rails.logger.warn("[Base] Failed to standardize tool call: #{e.message}")
        nil
      end

      # Helper: Build standardized tool result with proper is_error field
      # Ensures all adapters consistently include is_error to inform LLM of execution status
      #
      # @param tool_result [Hash] Tool result from CoreLoop with :call_id, :result, :is_error
      # @param base_format [Hash] Provider-specific base format (type, tool_use_id/tool_call_id, etc.)
      # @return [Hash] Standardized result with is_error field included if present
      #
      # Example usage in adapter:
      #   result = standardize_tool_result(tr, {
      #     'type' => 'tool_result',
      #     'tool_use_id' => tr[:call_id],
      #     'content' => tr[:result].to_s
      #   })
      def standardize_tool_result(tool_result, base_format)
        # Include is_error if present (critical for LLM to understand execution status)
        base_format['is_error'] = tool_result[:is_error] if tool_result.key?(:is_error)
        base_format
      end

      private

      # Rate limit retry configuration
      LLM_RATE_LIMIT_RETRIES = 3
      LLM_RATE_LIMIT_BASE_DELAY = 2.0 # seconds

      # Common HTTP helpers
      def http_post_json(url, headers:, body:)
        retries = 0

        loop do
          uri = URI.parse(url)
          req = Net::HTTP::Post.new(uri)
          headers.each { |k, v| req[k] = v }
          req['Content-Type'] = 'application/json'
          req.body = JSON.dump(body)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = 120

          res = http.request(req)

          if res.is_a?(Net::HTTPSuccess)
            return JSON.parse(res.body)
          end

          error_body = res.body.to_s
          error_summary = error_body[0..500]  # First 500 chars for log

          # Handle rate limiting with exponential backoff
          if res.code == '429'
            retries += 1
            if retries <= LLM_RATE_LIMIT_RETRIES
              # Check for Retry-After header
              retry_after = res['Retry-After']&.to_i || (LLM_RATE_LIMIT_BASE_DELAY * (2 ** (retries - 1)))
              Rails.logger.warn("[LLM API] Rate limited (429), retry #{retries}/#{LLM_RATE_LIMIT_RETRIES} after #{retry_after}s")
              sleep(retry_after)
              next
            else
              Rails.logger.error("[LLM API] Rate limit retries exhausted after #{LLM_RATE_LIMIT_RETRIES} attempts")
            end
          end

          # Log error details
          Rails.logger.error("[LLM API] #{res.code} error: #{error_summary}")
          Rails.logger.error("[LLM API] Full error body: #{error_body}")

          raise "API error: #{res.code} - #{error_summary}"
        end
      end

      def http_post_stream(url, headers:, body:, &block)
        uri = URI.parse(url)
        req = Net::HTTP::Post.new(uri)
        headers.each { |k, v| req[k] = v }
        req['Content-Type'] = 'application/json'
        req['Accept'] = 'text/event-stream'
        req.body = JSON.dump(body)

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
          http.request(req) do |response|
            unless response.is_a?(Net::HTTPSuccess)
              error_body = response.body.to_s
              Rails.logger.error("[LLM API Streaming] #{response.code} error: #{error_body[0..500]}")
              raise "API error: #{response.code} - #{error_body[0..200]}"
            end

            response.read_body do |chunk|
              yield chunk if block_given?
            end
          end
        end
      end
    end
  end
end
