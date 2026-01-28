# frozen_string_literal: true

# Single public interface for all LLM calls.
# Adapters are private implementation details - always use Service methods.
#
# Usage:
#   Llms::Service.call(...)        # Simple conversations, goal creation
#   Llms::Service.agent_call(...)  # Agent execution with policy & streaming
module Llms
  class Service
    # Error raised when circuit breaker is open
    class CircuitOpenError < StandardError; end

    # ========================================================================
    # PUBLIC API - Use these methods for all LLM calls
    # ========================================================================

    # Simple LLM call for conversations and one-off queries
    #
    # @param system [String] System prompt
    # @param messages [Array<Hash>] Message history with :role and :content
    # @param tools [Array<Hash>] Optional tool definitions
    # @param user [User] Optional user for adapter selection
    # @param agentable [Goal|AgentTask|UserAgent] Optional for adapter selection
    # @param use_case [Symbol] Optional use case (:agents, :tasks, :summaries) - auto-detects if not provided
    # @param stream [Boolean] Enable streaming (requires block)
    # @yield [String|Hash] Yields text chunks or structured events if streaming
    # @return [Hash] { content: Array, tool_calls: Array, usage: Hash }
    def self.call(system:, messages:, tools: nil, user: nil, agentable: nil, use_case: nil, stream: false, &block)
      use_case ||= agentable.is_a?(AgentTask) ? :tasks : :agents
      context = if agentable
                  "#{agentable.class.name.underscore}_#{agentable.id}"
                elsif use_case == :summaries
                  'web_summarization'
                else
                  'llm_call'
                end
      adapter = Adapters.for(use_case, user: user, agentable: agentable, context: context)
      provider = adapter.class.name.demodulize.gsub('Adapter', '').underscore.to_sym

      # Check circuit breaker before making call
      unless ConnectivityTracker.circuit_allows?(provider)
        raise CircuitOpenError, "Circuit breaker open for #{provider}, try again later"
      end

      # Format tools for provider
      provider_tools = tools.present? ? adapter.format_tool_definitions(tools) : nil

      # Make request with proper streaming
      start_time = Time.current
      response = adapter.make_request(
        messages: messages,
        system: system,
        tools: provider_tools,
        stream: stream && block_given?,
        &block
      )

      # Track successful call
      duration_ms = ((Time.current - start_time) * 1000).round
      ConnectivityTracker.record_success(provider, duration_ms: duration_ms, source: 'usage')
      ConnectivityTracker.circuit_success(provider)

      # Track costs
      adapter.extract_and_track_usage(response)

      # Extract tool calls
      tool_calls = adapter.extract_tool_calls(response)

      # Format content consistently
      content = extract_content(response)

      { content: content, tool_calls: tool_calls, usage: response['_usage'] || {} }
    rescue CircuitOpenError
      # Re-raise circuit open errors without tracking (already logged)
      raise
    rescue => e
      # Track failed call and update circuit breaker
      provider = adapter&.class&.name&.demodulize&.gsub('Adapter', '')&.underscore&.to_sym
      if provider
        ConnectivityTracker.record_failure(provider, error: e.message, source: 'usage')
        ConnectivityTracker.circuit_failure(provider)
      end

      Rails.logger.error("[Llms::Service] call error: #{e.class}: #{e.message}")
      raise
    end

    # Agent execution with policy, streaming, and structured events
    # Always streams and applies Tools::Policy for UI filtering
    #
    # @param agentable [Goal|AgentTask|UserAgent] Agent context
    # @param user [User] User context
    # @param system [String] System prompt
    # @param messages [Array<Hash>] Message history
    # @param tools [Array<Hash>] Tool definitions
    # @yield [Hash] Structured events: { type: :think|:tool_start|:tool_complete, data: {...} }
    # @return [Hash] { response: Hash, tool_calls: Array, policy: Tools::Policy }
    def self.agent_call(agentable:, user:, system:, messages:, tools:, &block)
      use_case = agentable.is_a?(AgentTask) ? :tasks : :agents
      context = "#{agentable.class.name.underscore}_#{agentable.id}"
      adapter = Adapters.for(use_case, user: user, agentable: agentable, context: context)
      provider = adapter.class.name.demodulize.gsub('Adapter', '').underscore.to_sym

      # Check circuit breaker before making call
      unless ConnectivityTracker.circuit_allows?(provider)
        raise CircuitOpenError, "Circuit breaker open for #{provider}, try again later"
      end

      # Create policy for UI filtering
      policy = Tools::Policy.new

      # Format tools for provider
      provider_tools = adapter.format_tool_definitions(tools)

      # Accumulate streamed text for thinking
      streamed_text = +""

      # Track send_message streaming state
      send_message_buffers = {} # tool_id => { json_buffer:, text_buffer:, text_sent: }

      # Always stream for agents - make request with structured event handling
      start_time = Time.current
      response = adapter.make_request(
        messages: messages,
        system: system,
        tools: provider_tools,
        stream: true
      ) do |delta|
        # Handle different delta types
        if delta.is_a?(String) && delta.present?
          # Text delta - internal reasoning/thinking
          streamed_text << delta
          block&.call({ type: :think, data: { text: delta } })
        elsif delta.is_a?(Hash)
          # Structured streaming events from adapter
          event_type = delta[:type] || delta['type']
          case event_type
          when 'tool_start'
            tool_name = delta[:tool_name] || delta['tool_name']
            tool_id = delta[:tool_id] || delta['tool_id']
            # Apply policy - only surface one tool
            if policy.consider_tool_start(tool_name, tool_id)
              block&.call({
                type: :tool_start,
                data: {
                  tool_name: tool_name,
                  tool_id: tool_id
                }
              })
            end
          when 'send_message_chunk'
            # Real-time streaming of send_message text parameter from Anthropic input_json_delta
            tool_id = delta[:tool_id]
            partial_json = delta[:partial_json]

            # Initialize buffer for this tool
            send_message_buffers[tool_id] ||= {
              json_buffer: +'',
              text_sent: 0
            }
            buffer = send_message_buffers[tool_id]

            # Accumulate JSON chunks
            buffer[:json_buffer] << partial_json

            # Use json_completer gem for production-grade incremental JSON parsing
            # Handles incomplete JSON, escape sequences, nested structures properly
            begin
              # Complete the accumulated partial JSON to extract current state
              completed_json = JsonCompleter.complete(buffer[:json_buffer])
              parsed = JSON.parse(completed_json)

              # Extract text field if present
              if parsed['text']
                full_text = parsed['text']

                # Stream only NEW text since last extraction (incremental delta)
                if full_text.length > buffer[:text_sent]
                  new_text = full_text[buffer[:text_sent]..-1]
                  buffer[:text_sent] = full_text.length

                  # Stream the new text chunk to UI
                  # Anthropic streams ~30 chunks/5s avg 163ms/chunk for real-time feel
                  unless new_text.empty?
                    block&.call({
                      type: :send_message_stream,
                      data: { tool_id: tool_id, text_chunk: new_text }
                    })
                  end
                end
              end
            rescue JSON::ParserError => e
              # json_completer should prevent this, but log if it happens
              Rails.logger.warn("[LLM Service] JSON parse error in send_message streaming: #{e.message}")
            end
          when 'tool_complete'
            tool_name = delta[:tool_name] || delta['tool_name']
            tool_id = delta[:tool_id] || delta['tool_id']
            tool_input = delta[:tool_input] || delta['tool_input'] || {}
            # Apply policy - only surface the selected tool
            if policy.consider_tool_complete(tool_name, tool_id)
              block&.call({
                type: :tool_complete,
                data: {
                  tool_name: tool_name,
                  tool_id: tool_id,
                  tool_input: tool_input
                }
              })
            end
          end
        end
      end

      # Track successful call
      duration_ms = ((Time.current - start_time) * 1000).round
      ConnectivityTracker.record_success(provider, duration_ms: duration_ms, source: 'agent')
      ConnectivityTracker.circuit_success(provider)

      # Track costs - extract from the actual response
      begin
        adapter.extract_and_track_usage(response)
      rescue => e
        Rails.logger.error("[Llms::Service] Cost tracking failed in agent_call: #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
      end

      # Extract tool calls
      tool_calls = adapter.extract_tool_calls(response)

      {
        response: response,
        tool_calls: tool_calls,
        policy: policy,
        streamed_text: streamed_text
      }
    rescue CircuitOpenError
      # Re-raise circuit open errors without tracking (already logged)
      raise
    rescue => e
      # Track failed call and update circuit breaker
      provider = adapter&.class&.name&.demodulize&.gsub('Adapter', '')&.underscore&.to_sym
      if provider
        ConnectivityTracker.record_failure(provider, error: e.message, source: 'agent')
        ConnectivityTracker.circuit_failure(provider)
      end

      Rails.logger.error("[Llms::Service] agent_call error: #{e.class}: #{e.message}")
      raise
    end

    # Summarize web content
    #
    # @param content [String] Web page content to summarize
    # @param url [String] Source URL
    # @param title [String] Page title
    # @param description [String] Optional meta description
    # @param user [User] User for cost tracking
    # @param length [Symbol] Summary length (:concise, :detailed)
    # @return [String] Markdown-formatted summary
    def self.summarize(content:, url:, title:, description: nil, user:, length: :concise)
      # Build prompts
      system_prompt = Prompts::Summarization.system_prompt
      user_prompt = Prompts::Summarization.user_prompt(
        url: url,
        title: title,
        description: description,
        content: content,
        length: length
      )

      # Call LLM with summaries use case (uses cheaper Haiku model)
      result = call(
        system: system_prompt,
        messages: [{ role: "user", content: user_prompt }],
        user: user,
        use_case: :summaries
      )

      # Extract and return text
      result[:content]
        .select { |block| block[:type] == :text }
        .map { |block| block[:text] }
        .join("\n")
        .strip
    rescue => e
      Rails.logger.error("[Llms::Service] summarize error: #{e.class}: #{e.message}")
      raise
    end

    # ========================================================================
    # PRIVATE HELPERS
    # ========================================================================

    # Extract content array from response
    # Adapters should return consistent format via normalize_response_for_history(),
    # but this provides backward compatibility for Service.call() usage
    def self.extract_content(response)
      return [] unless response.is_a?(Hash)

      # Standard format: array of content blocks from adapters
      if response['content'].is_a?(Array)
        response['content'].map do |blk|
          if blk.is_a?(Hash)
            { type: blk['type']&.to_sym || :text, text: blk['text'] || '' }
          else
            { type: :text, text: blk.to_s }
          end
        end
      # Legacy fallback for older code paths (should be rare with normalized adapters)
      elsif response[:text] || response['text']
        Rails.logger.warn("[Service] Response using legacy text format instead of content blocks")
        [{ type: :text, text: response[:text] || response['text'] }]
      else
        Rails.logger.warn("[Service] Unexpected response format: #{response.keys}")
        [{ type: :text, text: response.to_s }]
      end
    end
    private_class_method :extract_content

    # Utility: strip Markdown code fences (``` or ```json) from model output
    def self.strip_code_fences(text)
      return nil if text.nil?
      s = text.to_s.strip
      if s.start_with?("```")
        s = s.gsub(/^```[a-zA-Z0-9_\-]*\s*/m, '')
        s = s.gsub(/```\s*$/m, '')
      end
      s.strip
    end
  end
end
