# frozen_string_literal: true

module Agents
  # Handles errors from agent execution: retry logic, error messages, notifications
  class ErrorHandler
    def initialize(agentable:, user:, context:, stream_channel:)
      @agentable = agentable
      @user = user
      @context = context
      @stream_channel = stream_channel
    end

    def handle(error)
      # Find first line of OUR code (not gems) to show WHERE in our app it failed
      app_trace = error.backtrace.find { |line| line.include?('/app/') }

      Rails.logger.error("[ErrorHandler] Error in #{@agentable.class.name}##{@agentable.id}: #{error.class}: #{error.message}")
      Rails.logger.error("[ErrorHandler] Failed at: #{app_trace}") if app_trace

      # Only log full backtrace in development for debugging
      if Rails.env.development?
        Rails.logger.debug("[ErrorHandler] Full backtrace:")
        Rails.logger.debug(error.backtrace.first(10).join("\n"))
      end

      if retryable?(error)
        handle_retryable_error(error)
      else
        handle_permanent_error(error)
      end
    end

    private

    # ========================================================================
    # RETRYABLE ERRORS
    # ========================================================================

    def handle_retryable_error(error)
      attempt_count = current_attempt_count
      max_retries = max_retries_for(error)

      # Check if we've exceeded max retries
      if attempt_count >= max_retries
        handle_max_retries_exceeded(error, attempt_count)
        return
      end

      # Create error message with countdown
      retry_delay = calculate_retry_delay(error, attempt_count)
      create_error_message(error, retry_delay, attempt_count)

      # Stream error notification
      stream_error_notification(error, retry_delay)

      # Schedule retry
      schedule_retry(error, retry_delay, attempt_count)

      Rails.logger.warn("[ErrorHandler] Retryable error (attempt #{attempt_count + 1}/#{max_retries}), retry in #{retry_delay.round}s")
    end

    def handle_max_retries_exceeded(error, attempt_count)
      Rails.logger.error("[ErrorHandler] Max retries exceeded for #{@agentable.class.name}##{@agentable.id}")

      # Update existing error message or create new one
      if @context['error_message_id']
        update_error_message_permanent_failure(attempt_count)
      else
        create_permanent_failure_message(error, attempt_count)
      end

      # Mark task as cancelled if applicable
      @agentable.update!(status: :cancelled, result_summary: "Failed after #{attempt_count} retries") if @agentable.task?

      # Stream permanent failure
      stream_permanent_failure(attempt_count)
    end

    # ========================================================================
    # PERMANENT ERRORS
    # ========================================================================

    def handle_permanent_error(error)
      Rails.logger.error("[ErrorHandler] Non-retryable error: #{error.message}")

      # Create error message
      ThreadMessage.create!(
        user: @user,
        agentable: @agentable,
        source: :error,
        content: user_friendly_message(error),
        metadata: {
          error_type: error.class.name,
          technical_details: error.message,
          timestamp: Time.current.iso8601,
          retryable: false,
          triggering_message_ids: @context['processed_message_ids'] || []
        }
      )

      # Stream error notification
      stream_error_notification(error)

      # Mark task as cancelled if applicable
      @agentable.update!(status: :cancelled, result_summary: "Task failed: #{error.message}") if @agentable.task?
    end

    # ========================================================================
    # ERROR MESSAGES
    # ========================================================================

    def create_error_message(error, retry_delay, attempt_count)
      next_retry_at = Time.current + retry_delay.seconds

      msg = ThreadMessage.create!(
        user: @user,
        agentable: @agentable,
        source: :error,
        content: user_friendly_message(error, retry_delay),
        metadata: {
          error_type: error.class.name,
          technical_details: error.message,
          timestamp: Time.current.iso8601,
          retryable: true,
          next_retry_at: next_retry_at.iso8601,
          retry_delay_seconds: retry_delay.round,
          attempt_count: attempt_count + 1,
          agentable_type: @agentable.class.name,
          agentable_id: @agentable.id,
          triggering_message_ids: @context['processed_message_ids'] || []
        }
      )

      @context['error_message_id'] = msg.id
      Rails.logger.info("[ErrorHandler] Created error message #{msg.id} with retry in #{retry_delay.round}s")
    rescue => e
      Rails.logger.error("[ErrorHandler] Failed to create error message: #{e.message}")
    end

    def update_error_message_permanent_failure(attempt_count)
      msg = ThreadMessage.find_by(id: @context['error_message_id'])
      return unless msg

      msg.update!(
        content: "Failed after #{attempt_count} retry attempts. Please try again later.",
        metadata: msg.metadata.merge(retryable: false, failed_permanently: true)
      )
    end

    def create_permanent_failure_message(error, attempt_count)
      ThreadMessage.create!(
        user: @user,
        agentable: @agentable,
        source: :error,
        content: "Failed after #{attempt_count} retry attempts. Please try again later.",
        metadata: {
          error_type: error.class.name,
          technical_details: error.message,
          timestamp: Time.current.iso8601,
          retryable: false,
          failed_permanently: true,
          attempt_count: attempt_count,
          triggering_message_ids: @context['processed_message_ids'] || []
        }
      )
    end

    def user_friendly_message(error, retry_delay = nil)
      delay_text = retry_delay ? " in #{retry_delay.round}s" : ""

      case error.message
      when /rate_limit|429/i
        "Rate limit hit. Retrying#{delay_text}..."
      when /timeout|connection/i
        "Connection timeout. Retrying#{delay_text}..."
      when /has_tool\?/i
        "Tool configuration issue. Retrying#{delay_text}..."
      else
        if retry_delay
          "Error occurred. Retrying#{delay_text}..."
        else
          "Something went wrong: #{error.message}"
        end
      end
    end

    # ========================================================================
    # STREAMING NOTIFICATIONS
    # ========================================================================

    def stream_error_notification(error, retry_delay = nil)
      return unless @stream_channel

      Streams::Broker.publish(@stream_channel, event: :error, data: {
        code: error.class.name,
        message: user_friendly_message(error, retry_delay)
      })
    end

    def stream_permanent_failure(attempt_count)
      return unless @stream_channel

      Streams::Broker.publish(@stream_channel, event: :error, data: {
        code: 'MaxRetriesExceeded',
        message: "Failed after #{attempt_count} retry attempts"
      })
    end

    # ========================================================================
    # RETRY LOGIC
    # ========================================================================

    def schedule_retry(error, retry_delay, attempt_count)
      if @agentable.task?
        # Tasks: Use existing pause mechanism
        error_type = error.message.match?(/rate_limit|429/i) ? :rate_limit : :network
        @agentable.pause_with_error!(error_type, error.message, retry_delay)
      else
        # Goals/UserAgent: Retry via Sidekiq with updated context
        retry_context = @context.merge('retry_count' => attempt_count + 1)

        Agents::Orchestrator.perform_in(
          retry_delay.seconds,
          @agentable.class.name,
          @agentable.id,
          retry_context
        )

        Rails.logger.info("[ErrorHandler] Scheduled retry for #{@agentable.class.name}##{@agentable.id} in #{retry_delay.round}s")
      end
    end

    def current_attempt_count
      if @agentable.respond_to?(:retry_count)
        @agentable.retry_count || 0
      else
        @context['retry_count'] || 0
      end
    end

    def max_retries_for(error)
      if error.message.match?(/rate_limit|429/i)
        Constants::MAX_RETRIES_RATE_LIMIT
      elsif error.message.match?(/timeout|connection/i)
        Constants::MAX_RETRIES_NETWORK
      else
        Constants::MAX_RETRIES_DEFAULT
      end
    end

    def calculate_retry_delay(error, attempt_count)
      base_delay = if error.message.match?(/rate_limit|429/i)
        Constants::RATE_LIMIT_BASE_DELAY
      else
        Constants::NETWORK_ERROR_BASE_DELAY
      end

      delay = base_delay * (2 ** attempt_count)
      [delay, Constants::MAX_RETRY_DELAY].min + rand(Constants::RETRY_JITTER_RANGE)
    end

    def retryable?(error)
      error.message.match?(/rate_limit|429|timeout|connection|has_tool\?/i) ||
        (defined?(Net::TimeoutError) && error.is_a?(Net::TimeoutError))
    end
  end
end
