# frozen_string_literal: true

module Llms
  # Health check for LLM provider configuration and connectivity
  # Used by admin dashboard and CLI status command
  class HealthCheck
    USE_CASES = [:agents, :tasks, :summaries].freeze
    PROVIDERS = [:anthropic, :openai, :openrouter, :ollama].freeze

    class Result
      attr_reader :status, :message, :details

      def initialize(status:, message:, details: {})
        @status = status # :healthy, :warning, :error
        @message = message
        @details = details
      end

      def healthy?
        @status == :healthy
      end

      def warning?
        @status == :warning
      end

      def error?
        @status == :error
      end
    end

    # Full health check - configuration + connectivity
    def self.check_all
      {
        configuration: check_configuration,
        connectivity: connectivity_status,
        recent_errors: check_recent_errors
      }
    end

    # Get live connectivity status from tracker (fast, no API calls)
    def self.connectivity_status
      ConnectivityTracker.get_all_statuses
    end

    # Check ENV configuration for all use cases
    def self.check_configuration
      results = {}

      USE_CASES.each do |use_case|
        results[use_case] = check_use_case_config(use_case)
      end

      results
    end

    # Check connectivity by making a minimal test call
    def self.check_connectivity(timeout: 10)
      results = {}

      # Get unique providers from all use cases
      providers_in_use = []
      USE_CASES.each do |use_case|
        begin
          provider, _model = Adapters.send(:parse_config_for_use_case, use_case)
          providers_in_use << provider unless providers_in_use.include?(provider)
        rescue Adapters::ConfigurationError
          # Skip if not configured
        end
      end

      # Test each provider in use
      providers_in_use.each do |provider|
        results[provider] = test_provider_connection(provider, timeout: timeout)
      end

      results
    end

    # Check for recent LLM errors (last 24 hours)
    def self.check_recent_errors(since: 24.hours.ago)
      # Look for failed LLM costs or error patterns
      # Since we track costs, we can infer errors from missing expected costs
      # or by checking if there are any system-level errors logged

      recent_costs = LlmCost.where('created_at >= ?', since)
      total_calls = recent_costs.count

      # Calculate error rate by provider (if we tracked failures separately)
      # For now, just return stats
      {
        period: "Last 24 hours",
        total_calls: total_calls,
        by_provider: recent_costs.group(:provider).count,
        by_model: recent_costs.group(:model).count
      }
    end

    # Check individual use case configuration
    def self.check_use_case_config(use_case)
      env_key = case use_case
                when :agents then 'LLM_AGENTS_MODEL'
                when :tasks then 'LLM_TASKS_MODEL'
                when :summaries then 'LLM_SUMMARIES_MODEL'
                end

      config = ENV[env_key]

      # Not set
      if config.blank?
        return Result.new(
          status: :error,
          message: "#{env_key} not set",
          details: { env_key: env_key, example: "anthropic:sonnet-4.5" }
        )
      end

      # Invalid format
      unless config.include?(':')
        return Result.new(
          status: :error,
          message: "Invalid format: #{config}",
          details: { env_key: env_key, value: config, expected: "provider:model" }
        )
      end

      provider, model = config.split(':', 2)

      # Empty model
      if model.blank?
        return Result.new(
          status: :error,
          message: "Model not specified",
          details: { env_key: env_key, value: config }
        )
      end

      # Check API key
      api_key_result = check_api_key(provider.to_sym)
      if api_key_result.error?
        return Result.new(
          status: :error,
          message: api_key_result.message,
          details: { env_key: env_key, provider: provider, model: model }
        )
      end

      # All good
      Result.new(
        status: :healthy,
        message: "Configured: #{provider}:#{model}",
        details: {
          env_key: env_key,
          provider: provider,
          model: model,
          api_key_status: api_key_result.message
        }
      )
    rescue => e
      Result.new(
        status: :error,
        message: "Error checking config: #{e.message}",
        details: { env_key: env_key, error: e.class.name }
      )
    end

    # Check if API key is set for provider
    def self.check_api_key(provider)
      # Ollama doesn't require API key
      if provider == :ollama
        return Result.new(
          status: :healthy,
          message: "No API key required (local)",
          details: { provider: provider }
        )
      end

      env_key = "#{provider.to_s.upcase}_API_KEY"
      api_key = ENV[env_key]

      if api_key.blank?
        return Result.new(
          status: :error,
          message: "#{env_key} not set",
          details: { env_key: env_key, provider: provider }
        )
      end

      # Check key format (basic validation)
      if api_key.length < 10
        return Result.new(
          status: :warning,
          message: "API key seems too short",
          details: { env_key: env_key, length: api_key.length }
        )
      end

      Result.new(
        status: :healthy,
        message: "API key set (#{api_key[0..6]}...)",
        details: { env_key: env_key, key_prefix: api_key[0..6] }
      )
    end

    # Test provider connectivity with minimal call
    def self.test_provider_connection(provider, timeout: 10)
      adapter = Adapters.get(provider.to_sym)

      # Make a minimal test call
      start_time = Time.current
      response = Timeout.timeout(timeout) do
        adapter.call(
          messages: [{ role: 'user', content: 'ping' }],
          max_tokens: 10,
          stream: false
        )
      end
      duration = Time.current - start_time

      if response && response[:content].present?
        Result.new(
          status: :healthy,
          message: "Connected (#{(duration * 1000).round}ms)",
          details: {
            provider: provider,
            response_time_ms: (duration * 1000).round,
            responded: true
          }
        )
      else
        Result.new(
          status: :warning,
          message: "Unexpected response format",
          details: {
            provider: provider,
            response: response
          }
        )
      end
    rescue Timeout::Error
      Result.new(
        status: :error,
        message: "Timeout after #{timeout}s",
        details: { provider: provider, timeout: timeout }
      )
    rescue Faraday::Error => e
      Result.new(
        status: :error,
        message: "Connection error: #{e.message}",
        details: { provider: provider, error: e.class.name }
      )
    rescue Adapters::ConfigurationError => e
      Result.new(
        status: :error,
        message: e.message,
        details: { provider: provider, error: 'ConfigurationError' }
      )
    rescue => e
      Result.new(
        status: :error,
        message: "Error: #{e.message}",
        details: { provider: provider, error: e.class.name, backtrace: e.backtrace.first(3) }
      )
    end

    # Get summary of all providers and their availability
    def self.provider_summary
      summary = {}

      PROVIDERS.each do |provider|
        api_key_result = check_api_key(provider)

        # Check if provider is used in any use case
        used_in = []
        USE_CASES.each do |use_case|
          begin
            configured_provider, _model = Adapters.send(:parse_config_for_use_case, use_case)
            used_in << use_case if configured_provider == provider
          rescue
            # Not configured for this use case
          end
        end

        summary[provider] = {
          api_key_status: api_key_result.status,
          api_key_message: api_key_result.message,
          used_in: used_in,
          configured: !used_in.empty?
        }
      end

      summary
    end
  end
end
