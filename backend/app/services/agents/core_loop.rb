# frozen_string_literal: true

module Agents
  # Pure ReAct pattern implementation: LLM call → execute tools → add results → repeat until LLM stops calling tools
  # Single iteration loop that continues until natural completion
  class CoreLoop

    def initialize(user:, agentable:, tools:, stream_channel:)
      @user = user
      @agentable = agentable
      @tools = tools
      @stream_channel = stream_channel
      @tools_called = []  # Track tools called during execution
    end

    # Pure ReAct loop: continues until LLM makes no tool calls (natural completion)
    def run!(message:, system_prompt:, max_iterations: Constants::MAX_ITERATIONS, on_think: nil)
      # === SETUP ===
      @on_think = on_think

      # Get conversation history
      msgs = HistoryManager.get_messages(@agentable)

      # Get adapter once and reuse (used for cost tracking and formatting)
      use_case = @agentable.task? ? :tasks : :agents
      @adapter = Llms::Adapters.for(use_case, user: @user, agentable: @agentable, context: "#{@agentable.class.name.underscore}_#{@agentable.id}")

      # Add the initial message if provided (but don't persist to LLM history yet)
      # We'll only persist it if we actually make an API call
      if message.present?
        msgs << { role: 'user', content: message }
      end

      Rails.logger.info("[CoreLoop] Starting ReAct loop for #{@agentable.class.name} #{@agentable.id} with #{msgs.length} history messages")

      # === REACT LOOP ===
      # Continue until agent stops calling tools or max iterations reached
      iterations = 0
      natural_completion = false
      consecutive_message_calls = 0
      start_time = Time.current
      turn_id = nil  # Track current turn ID for streaming

      while iterations < max_iterations
        iterations += 1

        # === SAFETY CHECKS ===
        if iterations >= max_iterations
          Rails.logger.warn("[CoreLoop] #{@agentable.class.name} #{@agentable.id} hit max iterations (#{max_iterations})")
          # Add a system message to LLM history explaining why we stopped
          system_message = "System: Maximum iteration limit (#{max_iterations}) reached. Task execution stopped."
          HistoryManager.add_user_message(agentable: @agentable, content: system_message)
          break
        end

        if Time.current - start_time > Constants::MAX_EXECUTION_TIME
          Rails.logger.warn("[CoreLoop] #{@agentable.class.name} #{@agentable.id} hit max execution time (#{Constants::MAX_EXECUTION_TIME.inspect})")
          break
        end

        # Check message count to detect runaway loops (tasks only)
        if @agentable.task? && msgs.length > Constants::MAX_TASK_HISTORY_LENGTH
          Rails.logger.warn("[CoreLoop] Task #{@agentable.id} has #{msgs.length} messages (threshold: #{Constants::MAX_TASK_HISTORY_LENGTH}) - stopping to prevent runaway execution")
          break
        end

        Rails.logger.info("[CoreLoop] #{@agentable.class.name} #{@agentable.id} ReAct iteration #{iterations} with #{msgs.length} messages")

        # === CALL LLM ===
        begin
          turn_id = SecureRandom.uuid
          Streams::Broker.publish(@stream_channel, event: :turn_start, data: { turn_id: turn_id }) if @stream_channel
          rate_limit_retries = Constants::RATE_LIMIT_IMMEDIATE_RETRIES

          begin
            # Use Service.agent_call for clean streaming with policy
            provider_tools = @tools.provider_tools(context: @agentable.agent_type.to_sym)

            result = Llms::Service.agent_call(
              agentable: @agentable,
              user: @user,
              system: system_prompt,
              messages: msgs,
              tools: provider_tools
            ) do |event|
              handle_agent_event(event, turn_id)
            end

            response = result[:response]
            tool_calls = result[:tool_calls]
            policy = result[:policy]
            assistant_text = result[:streamed_text]
          rescue => api_err
            # Handle transient rate limits gracefully with a short backoff
            if api_err.message.include?('rate_limit_error') || api_err.message.include?('429')
              if rate_limit_retries > 0
                Rails.logger.warn("[CoreLoop] Rate limit hit, retrying (#{rate_limit_retries} attempts left)")
                sleep Constants::RATE_LIMIT_IMMEDIATE_DELAY
                rate_limit_retries -= 1
                retry
              else
                Rails.logger.error("[CoreLoop] Rate limit retries exhausted, failing")
              end
            end
            raise api_err
          end

          # On first iteration, persist the initial message to LLM history now that API call succeeded
          if iterations == 1 && message.present?
            HistoryManager.add_user_message(agentable: @agentable, content: message)
          end

          # Tool calls already extracted and filtered by policy in Service.agent_call
          # Policy ensures max 2 action tools + optional send_message
          all_tool_calls = tool_calls # Save ALL tool calls before filtering
          tool_calls = policy.filter_for_execution(tool_calls)

          # Persist assistant response to LLM history (adapter handles provider-specific cleanup)
          if assistant_text.present? || tool_calls.present?
            # Let adapter normalize response for history storage (filters empty blocks, etc.)
            # Per contract: returns Array of content blocks or nil
            assistant_content = @adapter.normalize_response_for_history(response)

            # Fallback: if normalization returned nil but we have streamed text, wrap it
            if assistant_content.nil? && assistant_text.present?
              assistant_content = [{ 'type' => 'text', 'text' => assistant_text }]
            end

            if assistant_content.present?
              msgs << { role: 'assistant', content: assistant_content }

              # Persist to LLM history - adapter contract ensures this is always an Array
              unless assistant_content.is_a?(Array)
                Rails.logger.error("[CoreLoop] Adapter #{@adapter.class} violated contract! normalize_response_for_history must return Array or nil, got: #{assistant_content.class}")
                assistant_content = [{ 'type' => 'text', 'text' => assistant_content.to_s }]
              end
              HistoryManager.add_assistant_message(agentable: @agentable, content: assistant_content)
            else
              # Empty response - treat as natural completion
              Rails.logger.warn("[CoreLoop] Empty response after normalization, treating as natural completion")
              natural_completion = true
              break
            end
          end

          # ReAct completion: if no tool calls, agent has decided it's done
          if tool_calls.blank?
            Rails.logger.info("[CoreLoop] #{@agentable.class.name} #{@agentable.id} completed naturally - no more tool calls")
            natural_completion = true
            
            # Note: Agent provided text without tools at completion
            # This is typically reasoning/thinking text, not meant for the user
            # If agent wants to send a message, it should use send_message tool explicitly
            if assistant_text.present?
              Rails.logger.debug("[CoreLoop] Agent completed with text (not sent): #{assistant_text[0..100]}...")
            end
            
            # Streaming cleanup
            if @stream_channel
              Streams::Broker.publish(@stream_channel, event: :done, data: { turn_id: turn_id })
            end
            break
          else
            # Agent provided text WITH tool calls - this is reasoning/explanation text
            # We should NOT persist this as a ThreadMessage since it's internal reasoning
            # The agent should use send_message tool for user-facing communication
            Rails.logger.debug("[CoreLoop] Agent provided text with tool calls - treating as internal reasoning")
          end

          # Signal that thinking is done, tools are about to execute
          Streams::Broker.publish(@stream_channel, event: :turn_done, data: { turn_id: turn_id }) if @stream_channel

          # Execute tools and get results
          tool_results = execute_tool_calls(tool_calls)

          # Add error results for tools filtered by policy
          # This ensures every tool_use has a matching tool_result (Anthropic requirement)
          executed_call_ids = tool_results.map { |r| r[:call_id] }
          filtered_tools = all_tool_calls.reject { |tc| executed_call_ids.include?(tc[:call_id]) }
          filtered_tools.each do |tc|
            Rails.logger.info("[CoreLoop] Adding policy-filtered result for tool: #{tc[:name]} (#{tc[:call_id]})")
            tool_results << {
              call_id: tc[:call_id],
              name: tc[:name],
              result: "Tool execution skipped by policy: max #{Tools::Policy::MAX_ACTION_TOOLS} action tools per turn. Use fewer parallel tool calls.",
              is_error: false  # Not an error, just policy enforcement
            }
          end

          # Add tool results to history FIRST, before any early breaks
          # This ensures provider always sees tool_use followed by tool_result
          if tool_results.any?
            # Format tool results using the adapter
            provider_tool_results = @adapter.format_tool_results(tool_results)

            # Validate that adapter returned results (catches missing implementations)
            if provider_tool_results.nil? || (provider_tool_results.is_a?(Array) && provider_tool_results.empty?)
              Rails.logger.error("[CoreLoop] Adapter #{@adapter.class} format_tool_results returned empty for #{tool_results.count} results - Tool details: #{tool_results.map { |r| "#{r[:name]}: #{r[:result][0..100]}" }.join(', ')}")
              raise "Adapter #{@adapter.class} doesn't properly implement format_tool_results"
            end

            msgs << { role: 'user', content: provider_tool_results }

            # Persist tool results to LLM history
            HistoryManager.add_user_message(agentable: @agentable, content: provider_tool_results)

            # Add iteration limit warnings when approaching max iterations
            remaining_iterations = max_iterations - iterations
            if remaining_iterations == 5
              warning = "System note: You have #{remaining_iterations} iterations remaining. Please prioritize completing your task efficiently."
              Rails.logger.info("[CoreLoop] Adding iteration warning: #{remaining_iterations} iterations left")
              HistoryManager.add_user_message(agentable: @agentable, content: warning)
              msgs << { role: 'user', content: warning }
            elsif remaining_iterations == 2
              warning = "System note: Only #{remaining_iterations} iterations left. You should wrap up your task now."
              Rails.logger.info("[CoreLoop] Adding iteration warning: #{remaining_iterations} iterations left")
              HistoryManager.add_user_message(agentable: @agentable, content: warning)
              msgs << { role: 'user', content: warning }
            elsif remaining_iterations == 1
              warning = "System note: This is your LAST iteration. You must complete your task now or it will be stopped."
              Rails.logger.info("[CoreLoop] Adding iteration warning: final iteration")
              HistoryManager.add_user_message(agentable: @agentable, content: warning)
              msgs << { role: 'user', content: warning }
            end

            # Anti-loop protection: check for repetitive tool usage
            sent_msg = tool_results.any? { |r| r[:name] == 'send_message' && r.dig(:details, :success) == true }

            if sent_msg
              consecutive_message_calls += 1
              Rails.logger.info("[CoreLoop] #{@agentable.class.name} #{@agentable.id} consecutive send_message calls: #{consecutive_message_calls}")

              # Conversational agents stop after sending a message
              if @agentable.conversational?
                Rails.logger.info("[CoreLoop] Conversational agent sent message, completing naturally")
                natural_completion = true
                break
              elsif consecutive_message_calls >= Constants::MAX_SAME_TOOL_CONSECUTIVE
                Rails.logger.warn("[CoreLoop] #{@agentable.class.name} #{@agentable.id} making repetitive send_message calls (#{consecutive_message_calls}), stopping")
                natural_completion = true
                break
              end
            else
              consecutive_message_calls = 0  # Reset counter
            end
          end
          
          # Small delay to prevent rate limiting
          delay_seconds = Rails.env.production? ? 1 : 0.3
          sleep(delay_seconds)
          
        rescue => e
          Rails.logger.error("[CoreLoop] Error in ReAct iteration #{iterations}: #{e.message}")
          Rails.logger.error(e.backtrace.first(10).join("\n"))

          # Stream error to UI before re-raising
          if @stream_channel
            Streams::Broker.publish(@stream_channel, event: :error, data: {
              code: e.class.name,
              message: "Error during agent execution"
            })
          end

          raise e
        end
      end

      # Note: LLM history is now persisted immediately after each turn (assistant responses and tool results)
      # No need to persist at the end since we do it in real-time

      {
        iterations: iterations,
        natural_completion: natural_completion,
        turn_id: turn_id,
        tools_called: @tools_called.uniq
      }
    end

    private

    def execute_tool_calls(tool_calls)
      results = []

      tool_calls.each do |tool_call|
        next unless tool_call.is_a?(Hash)

        # extract_tool_calls returns guaranteed standardized format: {name:, parameters:, call_id:}
        name = tool_call[:name]
        params = tool_call[:parameters] || {}
        call_id = tool_call[:call_id]
        parse_error = tool_call[:_parse_error]

        # Skip malformed tool calls
        next unless name.is_a?(String) && name.present?
        next unless call_id.is_a?(String) && call_id.present?
        next unless params.is_a?(Hash)

        begin
          # Check if this tool call had a JSON parse error during streaming
          if parse_error
            # Don't execute the tool - send an error result back to agent
            # Agent should retry 2-3 times with corrections
            error_message = "Tool parameter JSON parsing failed: #{parse_error[:error]}"
            error_message += "\nRaw JSON buffer: #{parse_error[:raw_json].inspect}" if parse_error[:raw_json].present?

            Rails.logger.warn("[CoreLoop] Skipping tool '#{name}' execution due to parse error: #{parse_error[:error]}")

            # Update ThreadMessage to mark tool as failed (it was created during streaming)
            # The ThreadMessage was created during content_block_start, we need to update it now
            activity_id = call_id || SecureRandom.uuid
            unless name == 'send_message'
              begin
                # Find and update the existing ThreadMessage that was created when tool started
                msg = ThreadMessage.where(
                  user: @user,
                  agentable: @agentable,
                  source: :agent,
                  message_type: :tool
                ).where("metadata -> 'tool_activity' ->> 'id' = ?", activity_id).first

                if msg
                  msg.update_tool_activity({
                    status: 'failure',
                    error: error_message
                  })
                  msg.update!(content: "") # Clear to trigger auto-generation
                  Rails.logger.info("[CoreLoop] Updated ThreadMessage #{msg.id} with parse error")
                end
              rescue => e
                Rails.logger.error("[CoreLoop] Failed to update ThreadMessage for parse error: #{e.message}")
              end
            end

            results << {
              call_id: call_id,
              name: name,
              result: error_message,
              is_error: true
            }
            next
          end

          # Publish tool_start for real-time UI and create initial ThreadMessage
          # Creates ThreadMessage immediately when tool starts for tool use cell
          # (except send_message which handles its own ThreadMessages)
          activity_id = call_id || SecureRandom.uuid

          unless name == 'send_message'
            @tools.create_tool_start_message(
              tool_name: name,
              params: params,
              activity_id: activity_id
            )
          end
          
          # Track tool call for activity logging
          @tools_called << name

          # Publish SSE event for tool execution start
          event_data = {
            tool_name: name,
            tool_id: activity_id,
            params: params
          }
          # Include task_id if this is a task agent
          event_data[:task_id] = @agentable.id if @agentable.is_a?(AgentTask)
          Streams::Broker.publish(@stream_channel, event: :tool_execution_start, data: event_data) if @stream_channel

          result = @tools.call(name, activity_id: activity_id, **params.symbolize_keys)
          
          # Publish SSE event for tool execution complete
          Streams::Broker.publish(@stream_channel, event: :tool_execution_complete, data: {
            tool_name: name,
            tool_id: activity_id,
            success: result[:success] || (result[:isError] == false),
            result: result
          }) if @stream_channel
          
          # Build simplified result for LLM conversation
          success = result[:success] || (result[:isError] == false)
          result_text = success ? (result[:result] || result[:observation] || 'Success') : (result[:error] || 'Failed')

          results << {
            name: name,
            result: result_text,
            details: result,
            call_id: call_id,
            is_error: !success
          }

          # Flag if send_message was used successfully to avoid duplicate final publish
          if name == 'send_message' && success
            @message_sent_this_turn = true
          end
          
        rescue => e
          Rails.logger.error("[CoreLoop] Tool execution failed: #{name} - #{e.message}")
          
          results << {
            name: name,
            result: "Error: #{e.message}",
            details: { success: false, error: e.message },
            call_id: call_id
          }
          
          # No direct SSE publish here; errors are reflected via ThreadMessage updates.
        end
      end
      
      results
    end

    # Handle structured events from Service.agent_call
    def handle_agent_event(event, turn_id)
      case event[:type]
      when :think
        # Internal reasoning text
        text = event[:data][:text]
        @on_think&.call(text)
        Streams::Broker.publish(@stream_channel, event: :think, data: { text: text, turn_id: turn_id }) if @stream_channel
      when :tool_start
        # Tool execution starting - create UI message
        tool_name = event[:data][:tool_name]
        tool_id = event[:data][:tool_id]
        @tools.create_tool_start_message(
          tool_name: tool_name,
          params: {},
          activity_id: tool_id
        )
      when :send_message_stream
        # Real-time streaming of send_message text parameter from LLM
        tool_id = event[:data][:tool_id]
        text_chunk = event[:data][:text_chunk]

        Rails.logger.info("[CoreLoop] send_message_stream event: chunk='#{text_chunk[0..30]}'")

        # Initialize streaming if first chunk
        @send_message_streaming ||= {}
        unless @send_message_streaming[tool_id]
          @send_message_streaming[tool_id] = true
          Rails.logger.info("[CoreLoop] Publishing :start event")
          Streams::Broker.publish(@stream_channel, event: :start, data: {}) if @stream_channel
        end

        # Stream the text chunk to UI
        Rails.logger.info("[CoreLoop] Publishing :chunk event with delta='#{text_chunk[0..30]}'")
        Streams::Broker.publish(@stream_channel, event: :chunk, data: { delta: text_chunk }) if @stream_channel
      when :tool_complete
        # Tool execution complete - update UI message with params
        tool_name = event[:data][:tool_name]
        tool_id = event[:data][:tool_id]
        tool_input = event[:data][:tool_input]

        # If this was send_message and we were streaming, mark streaming done
        if tool_name == 'send_message' && @send_message_streaming&.dig(tool_id)
          Streams::Broker.publish(@stream_channel, event: :done, data: {}) if @stream_channel
          @send_message_streaming.delete(tool_id)
        end

        @tools.update_tool_input_message(
          activity_id: tool_id,
          tool_name: tool_name,
          params: tool_input
        )
      end
    end

  end
end
