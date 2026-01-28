# frozen_string_literal: true

module Agents
  # Orchestrator: builds context and calls CoreLoop once
  # CoreLoop handles the ReAct pattern until natural completion
  class Orchestrator
    include Sidekiq::Worker
    sidekiq_options queue: :default, retry: false

    def perform(agentable_type, agentable_id, context = {})
      # === INITIALIZATION ===
      log_orchestrator "========== PERFORM CALLED =========="
      log_orchestrator "agentable_type: #{agentable_type}, agentable_id: #{agentable_id}"

      @agentable = agentable_type.constantize.find_by(id: agentable_id)
      unless @agentable
        Rails.logger.warn("[Orchestrator] Agentable not found: #{agentable_type}##{agentable_id}")
        return
      end

      @user = @agentable.user
      @context = context || {}
      @start_time = Time.current  # Track start time for activity logging

      Rails.logger.info("[Orchestrator] Starting for #{@agentable.class.name}##{@agentable.id}")
      log_orchestrator "User: #{@user.id}"

      # Skip if task is already in a terminal state
      if @agentable.task? && @agentable.status.in?(['completed', 'cancelled'])
        Rails.logger.info("[Orchestrator] Task #{@agentable.id} already #{@agentable.status}, skipping")
        return
      end

      # === SESSION MANAGEMENT ===
      # Archive stale session if timeout elapsed
      log_orchestrator "Checking for stale session..."
      archive_stale_session_if_needed!

      # Start or continue session
      log_orchestrator "Starting agent turn..."
      @agentable.start_agent_turn_if_needed!

      # === SETUP ===
      log_orchestrator "Calling setup..."
      setup!

      log_orchestrator "Attempting to claim execution lock..."
      lock_claimed = claim_execution_lock!
      unless lock_claimed
        Rails.logger.info("[Orchestrator] Could not claim lock for #{@agentable.class.name}##{@agentable.id} - agent already running")
        return
      end

      Rails.logger.info("[Orchestrator] Lock claimed for #{@agentable.class.name}##{@agentable.id}, proceeding with execution")

      begin
        # === EXECUTION ===
        log_orchestrator "Building context message..."
        Rails.logger.info("[Orchestrator] Step: build_context_message for #{@agentable.class.name}##{@agentable.id}")
        context_message = build_context_message
        Rails.logger.info("[Orchestrator] Context message built: #{context_message[0..200]}...")

        # Clean up any error messages from previous failed attempts (before retry succeeds)
        if @context['error_message_id']
          ThreadMessage.where(id: @context['error_message_id']).destroy_all
          Rails.logger.info("[Orchestrator] Cleaned up error message #{@context['error_message_id']} before retry")
        end

        # Validate and repair LLM history before running CoreLoop
        # This catches corruption from interrupted tool execution (e.g., Sidekiq restart)
        log_orchestrator "Validating LLM history..."
        validation_result = validate_and_repair_history!
        if validation_result.repaired?
          Rails.logger.warn("[Orchestrator] Repaired corrupted history before CoreLoop: #{validation_result.repairs.join(', ')}")
        end

        log_orchestrator "Calling run_core_loop..."
        Rails.logger.info("[Orchestrator] Step: run_core_loop for #{@agentable.class.name}##{@agentable.id}")
        result = run_core_loop(context_message)

        log_orchestrator "Calling handle_completion..."
        Rails.logger.info("[Orchestrator] Step: handle_completion for #{@agentable.class.name}##{@agentable.id}")
        handle_completion(result)
        log_orchestrator "Orchestrator completed successfully!"

      rescue => e
        # === ERROR HANDLING ===
        log_orchestrator "ERROR: #{e.class}: #{e.message}"
        handle_error(e)
      ensure
        # === CLEANUP ===
        log_orchestrator "Releasing lock and cleaning up..."
        release_execution_lock!
        teardown!
      end
    end

    private

    def setup!
      # For tasks, publish to parent's channel (where iOS is listening)
      # For goals, publish to goal's own channel
      stream_agentable = @agentable.respond_to?(:parent_agentable) ? (@agentable.parent_agentable || @agentable) : @agentable
      @stream_channel = Streams::Channels.for_agentable(agentable: stream_agentable)
      @tools = Tools::Registry.new(
        user: @user,
        goal: @agentable.associated_goal,
        task: @agentable.task? ? @agentable : nil,
        agentable: @agentable,
        context: @context
      )
    end

    def teardown!
      # For goal agents, transition back to waiting status when agent stops
      if @agentable.goal? && @agentable.working?
        @agentable.update!(status: :waiting)
        Rails.logger.info("[Orchestrator] Goal #{@agentable.id} transitioned back to waiting status")
      end
      
      # Publish completion notification for feed generation (if completion_channel provided)
      publish_completion_notification if @context&.dig("completion_channel")
    end

    # Simple job deduplication using database state
    def claim_execution_lock!
      @agentable.claim_execution_lock!
    end
    
    def release_execution_lock!
      @agentable.release_execution_lock!
    end

    # Validate LLM history and repair if corrupted
    # Returns HistoryValidator::Result with validation status and repairs made
    def validate_and_repair_history!
      validator = HistoryValidator.new(@agentable)
      validator.validate_and_repair!
    end

    def run_core_loop(message)
      # Build system prompt for this agent
      Rails.logger.info("[Orchestrator] Step: build_system_prompt for #{@agentable.class.name}##{@agentable.id}")
      system_prompt = build_system_prompt
      Rails.logger.info("[Orchestrator] System prompt built (#{system_prompt.length} chars)")

      # Pass message, system prompt, and stream channel to CoreLoop
      core_loop = Agents::CoreLoop.new(
        user: @user,
        agentable: @agentable,
        tools: @tools,
        stream_channel: @stream_channel
      )
      
      # All agents use same max iterations (CoreLoop has its own safety limits)
      max_iterations = 10
      
      # Only show thinking for tasks (autonomous work)
      on_think_callback = if @agentable.task?
        ->(text) { Streams::Broker.publish(@stream_channel, event: :think, data: { text: text }) }
      else
        nil
      end
      
      core_loop.run!(
        message: message,
        system_prompt: system_prompt,
        max_iterations: max_iterations,
        on_think: on_think_callback
      )
    end

    def handle_completion(result)
      Rails.logger.info("[Orchestrator] CoreLoop completed: #{result[:iterations]} iterations, natural_completion: #{result[:natural_completion]}")

      # Create AgentActivity record to track this execution
      create_agent_activity(result)

      # Mark task as completed if natural completion
      if @agentable.task? && result[:natural_completion]
        Rails.logger.info("[Orchestrator] Task completed naturally")

        # Generate meaningful summary from task's LLM history
        summary = TaskSummarizer.new(@agentable).summarize
        Rails.logger.info("[Orchestrator] Task summary: #{summary}")

        @agentable.update!(status: :completed, result_summary: summary)
      end

      if @agentable.user_agent?
        Rails.logger.info("[Orchestrator] UserAgent completed")
      end

      # Archive session if this was feed generation
      handle_feed_generation_completion
    end

    def handle_error(error)
      ErrorHandler.new(
        agentable: @agentable,
        user: @user,
        context: @context,
        stream_channel: @stream_channel
      ).handle(error)
    end

    # Build system prompt based on agent type
    def build_system_prompt
      if @agentable.goal?
        goal = @agentable
        notes_text = Llms::Prompts::Context.notes(goal: goal)
        Llms::Prompts::Goals.system_prompt(goal: goal, notes_text: notes_text)
      elsif @agentable.task?
        goal = @agentable.goal
        if goal
          # Task belongs to a goal
          notes_text = Llms::Prompts::Context.notes(goal: goal)
          Llms::Prompts::Tasks.system_prompt(goal: goal, task: @agentable, notes_text: notes_text)
        else
          # Standalone task (created by UserAgent, no goal association)
          notes_text = Llms::Prompts::Context.notes(user: @user)
          Llms::Prompts::Tasks.standalone_system_prompt(task: @agentable, notes_text: notes_text)
        end
      elsif @agentable.user_agent?
        notes_text = Llms::Prompts::Context.notes(user: @user)
        Llms::Prompts::UserAgent.system_prompt(user: @user, user_agent: @agentable, notes_text: notes_text)
      else
        raise "Unknown agentable type: #{@agentable.class.name}"
      end
    end
    
    # Publish completion notification to Redis for feed generation
    def publish_completion_notification
      channel = @context["completion_channel"]
      return unless channel

      message = {
        agentable_type: @agentable.class.name,
        agentable_id: @agentable.id,
        generation_id: @context["generation_id"],
        completed_at: Time.current.iso8601
      }

      Redis.current.publish(channel, message.to_json)
      Rails.logger.info("[Orchestrator] Published completion to #{channel}")
    rescue => e
      Rails.logger.warn("[Orchestrator] Failed to publish completion: #{e.message}")
      # Don't fail the orchestrator if Redis pub fails
    end

    # ========================================================================
    # CONTEXT BUILDING
    # ========================================================================
    # Determines what context message to build for the current execution.
    # Priority: check-in > feed generation > user messages > continuation

    def build_context_message
      return build_check_in_context if check_in_execution?
      return build_feed_generation_context if feed_generation?
      return build_user_message_context if has_user_messages?
      build_continuation_context
    end

    # === PRIORITY CHECKS ===

    def check_in_execution?
      @context["type"] == "agent_check_in"
    end

    def feed_generation?
      @context["type"] == "feed_generation"
    end

    def has_user_messages?
      ThreadMessage.has_unprocessed_for?(user: @user, agentable: @agentable)
    end

    # === CONTEXT BUILDERS ===
    # All delegate to prompts/ directory for actual prompt construction

    # 1. Check-in context (proactive agent self-scheduling)
    def build_check_in_context
      check_in_data = @context["check_in"]
      Rails.logger.info("[Orchestrator] Check-in execution for goal: #{@agentable.title}")

      Llms::Prompts::Goals.check_in_prompt(
        goal: @agentable,
        check_in_data: check_in_data
      )
    end

    # 2. Feed generation context (background feed generation job)
    def build_feed_generation_context
      # Only UserAgent participates in feed generation now
      # Goals create notes through check-ins and user messages naturally
      unless @agentable.user_agent?
        Rails.logger.warn("[Orchestrator] Feed generation called for non-UserAgent: #{@agentable.class.name}##{@agentable.id}")
        return "You should mark yourself complete. Feed generation is only for UserAgent."
      end

      Rails.logger.info("[Orchestrator] Feed generation for UserAgent")
      goals = @user.goals.active
      recent_insights = @user.user_agent.feed_insights.recent.limit(20)
      time_of_day = @context['time_of_day'] || 'morning'

      Llms::Prompts::UserAgent.feed_generation_prompt(
        user: @user,
        goals: goals,
        recent_insights: recent_insights,
        time_of_day: time_of_day
      )
    end

    # 2. User message context (user sent new messages)
    # Fetches unprocessed messages and marks them as processed
    # NOTE: CoreLoop will add to LLM history after successful API call
    def build_user_message_context
      messages = ThreadMessage.unprocessed_for_agent(
        user_id: @user.id,
        agentable: @agentable,
        source: :user
      ).to_a

      message_ids = messages.map(&:id)
      ThreadMessage.mark_processed!(message_ids)

      # Track processed message IDs for error handling (retry functionality)
      @context['processed_message_ids'] = message_ids

      messages.map(&:content).join("\n")
    rescue => e
      # Rollback processing status on error
      ThreadMessage.mark_unprocessed!(message_ids) if message_ids
      raise e
    end

    # 3. Continuation context (agent continuing existing conversation)
    def build_continuation_context
      prompt_module = @agentable.task? ? Llms::Prompts::Tasks : Llms::Prompts::Goals
      prompt_module.continuation_message(
        agentable: @agentable,
        user_requested_stop: user_requested_stop?
      )
    end

    # === HELPERS ===

    def user_requested_stop?
      recent_messages = ThreadMessage.where(agentable: @agentable, source: :user)
                                     .where('created_at > ?', Constants::USER_STOP_COMMAND_WINDOW.ago)
                                     .order(:created_at)
                                     .last(3)

      recent_messages.any? do |msg|
        content = msg.content.to_s.downcase.strip
        %w[stop cancel halt exit quit abort].include?(content)
      end
    end

    def parse_timestamp(timestamp)
      return nil if timestamp.blank?
      timestamp.is_a?(String) ? DateTime.parse(timestamp) : timestamp
    end

    # === SESSION ARCHIVING ===

    # Check for stale sessions and archive if timeout elapsed
    def archive_stale_session_if_needed!
      @agentable.with_lock do  # Prevent concurrent archiving
        current_history = @agentable.llm_history || []
        return if current_history.empty?

        turn_started_at = @agentable.current_turn_started_at
        return unless turn_started_at

        elapsed = Time.current - Time.parse(turn_started_at)

        if elapsed > Agents::Constants::SESSION_TIMEOUT
          log_orchestrator "Session stale (#{elapsed.to_i}s elapsed), archiving before new turn"
          @agentable.archive_agent_turn!(reason: 'session_timeout')
        end
      end
    end

    # Archive after feed generation completes
    def handle_feed_generation_completion
      return unless feed_generation?

      # Warn if feed generation completed without producing any insights
      insight_count = FeedInsight.where(user: @user)
                                 .where('created_at >= ?', @start_time)
                                 .count
      if insight_count == 0
        Rails.logger.warn(
          "[Orchestrator] Feed generation completed with 0 insights for user #{@user.id} " \
          "(period: #{@context['time_of_day'] || 'unknown'})"
        )
      end

      log_orchestrator "Feed generation complete (#{insight_count} insights), archiving session"
      @agentable.archive_agent_turn!(reason: 'feed_generation_complete')
    end

    # ========================================================================
    # AGENT ACTIVITY TRACKING
    # ========================================================================

    # Create AgentActivity record to track this execution
    # Aggregates LLM costs, tool usage, and execution metadata
    def create_agent_activity(result)
      return unless @start_time.present?

      end_time = Time.current

      # Aggregate LLM costs for this execution (costs created during the run)
      llm_costs = LlmCost.where(agentable: @agentable)
                         .where('created_at >= ? AND created_at <= ?', @start_time, end_time)

      input_tokens = llm_costs.sum(:input_tokens)
      output_tokens = llm_costs.sum(:output_tokens)
      cost_dollars = llm_costs.sum(:cost)
      cost_cents = (cost_dollars * 100).round

      # Extract tools called from result
      tools_called = result[:tools_called] || []

      # Create activity record
      AgentActivity.create!(
        agentable: @agentable,
        goal_id: @agentable.associated_goal&.id,
        agent_type: @agentable.agent_type,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        cost_cents: cost_cents,
        tools_called: tools_called,
        tool_count: tools_called.length,
        started_at: @start_time,
        completed_at: end_time,
        iterations: result[:iterations],
        natural_completion: result[:natural_completion] || false
      )

      Rails.logger.info("[Orchestrator] Created AgentActivity: #{input_tokens}+#{output_tokens} tokens, $#{cost_dollars.round(4)}, #{tools_called.length} tools")
    rescue => e
      # Don't fail the orchestrator if activity tracking fails
      Rails.logger.error("[Orchestrator] Failed to create AgentActivity: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
    end

    # ========================================================================
    # LOGGING
    # ========================================================================

    # Conditional logging: show puts in test env, otherwise use Rails.logger
    def log_orchestrator(message)
      if Rails.env.test?
        puts "[Orchestrator] ✓ #{message}"
      else
        Rails.logger.debug("[Orchestrator] #{message}")
      end
    end
  end
end
