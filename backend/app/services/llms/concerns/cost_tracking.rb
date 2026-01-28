# frozen_string_literal: true

module Llms
  module Concerns
    # Mixin for adapters to track LLM costs automatically
    module CostTracking
      def setup_tracking(user: nil, agentable: nil, context: nil)
        @tracking_user = user
        @tracking_agentable = agentable
        @tracking_context = context
        self
      end
      
      def track_usage(input_tokens:, output_tokens:, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, cached_tokens: 0)
        return unless @tracking_user

        cost = calculate_cost(
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          cache_creation_input_tokens: cache_creation_input_tokens,
          cache_read_input_tokens: cache_read_input_tokens,
          cached_tokens: cached_tokens
        )

        LlmCost.create!(
          user: @tracking_user,
          agentable: @tracking_agentable,
          provider: provider.to_s,
          model: model_key,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          cache_creation_input_tokens: cache_creation_input_tokens,
          cache_read_input_tokens: cache_read_input_tokens,
          cached_tokens: cached_tokens,
          cost: cost,
          context: @tracking_context
        )

        # Build log message with cache info if present
        log_parts = [
          "[LLM] user=#{@tracking_user.id} model=#{model_key}",
          "in=#{input_tokens} out=#{output_tokens}"
        ]

        # Add cache info to log if caching was used
        if cache_creation_input_tokens > 0
          log_parts << "cache_write=#{cache_creation_input_tokens}"
        end
        if cache_read_input_tokens > 0
          log_parts << "cache_read=#{cache_read_input_tokens}"
        end
        if cached_tokens > 0
          log_parts << "cached=#{cached_tokens}"
        end

        log_parts << "cost=#{LlmCost.format_cost(cost)}"
        log_parts << "context=#{@tracking_context}"

        Rails.logger.info(log_parts.join(' '))
      rescue => e
        Rails.logger.error("[LLM] Cost tracking failed: #{e.message}")
      end
      
      # Helper to extract usage from result and track
      # Public so it can be called from Service.agent_call
      def extract_and_track_usage(result)
        return result unless result.is_a?(Hash)

        usage = result[:usage] || result['_usage']
        return result unless usage

        input_tokens = usage[:input_tokens] || usage['input_tokens'] || 0
        output_tokens = usage[:output_tokens] || usage['output_tokens'] || 0

        # Extract cache-related tokens (Anthropic format)
        cache_creation_input_tokens = usage[:cache_creation_input_tokens] || usage['cache_creation_input_tokens'] || 0
        cache_read_input_tokens = usage[:cache_read_input_tokens] || usage['cache_read_input_tokens'] || 0

        # Extract cache-related tokens (OpenAI format)
        cached_tokens = usage[:cached_tokens] || usage['cached_tokens'] || 0

        track_usage(
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          cache_creation_input_tokens: cache_creation_input_tokens,
          cache_read_input_tokens: cache_read_input_tokens,
          cached_tokens: cached_tokens
        ) if input_tokens || output_tokens

        result
      end
    end
  end
end
