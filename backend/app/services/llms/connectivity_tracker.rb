# frozen_string_literal: true

module Llms
  # Tracks LLM provider connectivity status in Redis
  # Tests on server start if never tested or ENV changed
  # Updates status based on real usage
  # Implements circuit breaker pattern to prevent hammering unhealthy providers
  class ConnectivityTracker
    REDIS_PREFIX = "llm_connectivity"
    TEST_EXPIRY = 1.hour # Re-test after 1 hour if not used

    # Circuit breaker configuration
    FAILURE_THRESHOLD = 5     # Consecutive failures to trip circuit
    COOLDOWN_PERIOD = 60      # Seconds before allowing half-open test

    class << self
      def redis
        @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
      end

      # Check if provider needs testing (never tested or ENV changed)
      def needs_testing?(provider)
        # Check if we have any status
        status = get_status(provider)
        return true if status.nil?

        # Check if ENV changed since last test
        current_env_hash = env_hash_for_provider(provider)
        last_env_hash = redis.get("#{REDIS_PREFIX}:#{provider}:env_hash")

        return true if last_env_hash != current_env_hash

        # Check if status expired
        ttl = redis.ttl("#{REDIS_PREFIX}:#{provider}:status")
        return true if ttl && ttl < 0

        false
      end

      # Test provider with minimal call (cheapest possible)
      def test_provider(provider, timeout: 5)
        Rails.logger.info("[LLM Connectivity] Testing #{provider}...")

        start_time = Time.current
        begin
          adapter = Adapters.get(provider)

          # Minimal call: 1 token input, 1 token output = ~$0.000001-0.00001
          Timeout.timeout(timeout) do
            response = adapter.call(
              messages: [{ role: 'user', content: 'Hi' }],
              max_tokens: 1,
              stream: false
            )

            if response && response[:content].present?
              duration_ms = ((Time.current - start_time) * 1000).round
              record_success(provider, duration_ms: duration_ms, source: 'startup_test')
              Rails.logger.info("[LLM Connectivity] ✓ #{provider} OK (#{duration_ms}ms)")
              { success: true, duration_ms: duration_ms }
            else
              record_failure(provider, error: 'Empty response', source: 'startup_test')
              Rails.logger.warn("[LLM Connectivity] ✗ #{provider} returned empty response")
              { success: false, error: 'Empty response' }
            end
          end
        rescue Timeout::Error => e
          record_failure(provider, error: "Timeout after #{timeout}s", source: 'startup_test')
          Rails.logger.error("[LLM Connectivity] ✗ #{provider} timeout")
          { success: false, error: "Timeout after #{timeout}s" }
        rescue Faraday::Error => e
          record_failure(provider, error: e.message, source: 'startup_test')
          Rails.logger.error("[LLM Connectivity] ✗ #{provider} connection error: #{e.message}")
          { success: false, error: e.message }
        rescue => e
          record_failure(provider, error: e.message, source: 'startup_test')
          Rails.logger.error("[LLM Connectivity] ✗ #{provider} error: #{e.message}")
          { success: false, error: e.message }
        end
      end

      # Record successful call
      def record_success(provider, duration_ms: nil, source: 'usage')
        data = {
          status: 'healthy',
          last_success_at: Time.current.iso8601,
          last_test_at: Time.current.iso8601,
          duration_ms: duration_ms,
          source: source
        }.to_json

        redis.setex("#{REDIS_PREFIX}:#{provider}:status", TEST_EXPIRY, data)
        redis.setex("#{REDIS_PREFIX}:#{provider}:env_hash", TEST_EXPIRY, env_hash_for_provider(provider))
        redis.incr("#{REDIS_PREFIX}:#{provider}:success_count")

        # Clear failure count on success
        redis.del("#{REDIS_PREFIX}:#{provider}:failure_count")
        redis.del("#{REDIS_PREFIX}:#{provider}:last_error")
      end

      # Record failed call
      def record_failure(provider, error:, source: 'usage')
        data = {
          status: 'unhealthy',
          last_failure_at: Time.current.iso8601,
          last_test_at: Time.current.iso8601,
          last_error: error,
          source: source
        }.to_json

        redis.setex("#{REDIS_PREFIX}:#{provider}:status", TEST_EXPIRY, data)
        redis.setex("#{REDIS_PREFIX}:#{provider}:env_hash", TEST_EXPIRY, env_hash_for_provider(provider))
        redis.incr("#{REDIS_PREFIX}:#{provider}:failure_count")
        redis.setex("#{REDIS_PREFIX}:#{provider}:last_error", TEST_EXPIRY, error)
      end

      # Get current status for provider
      def get_status(provider)
        status_json = redis.get("#{REDIS_PREFIX}:#{provider}:status")
        return nil unless status_json

        status = JSON.parse(status_json)
        success_count = redis.get("#{REDIS_PREFIX}:#{provider}:success_count").to_i
        failure_count = redis.get("#{REDIS_PREFIX}:#{provider}:failure_count").to_i

        {
          status: status['status'],
          last_success_at: status['last_success_at'],
          last_failure_at: status['last_failure_at'],
          last_test_at: status['last_test_at'],
          last_error: status['last_error'],
          duration_ms: status['duration_ms'],
          source: status['source'],
          success_count: success_count,
          failure_count: failure_count
        }
      rescue JSON::ParserError => e
        Rails.logger.error("[LLM Connectivity] Failed to parse status: #{e.message}")
        nil
      end

      # Get status for all providers
      def get_all_statuses
        Llms::HealthCheck::PROVIDERS.map do |provider|
          [provider, get_status(provider)]
        end.to_h
      end

      # ========================================================================
      # CIRCUIT BREAKER
      # ========================================================================

      # Check if circuit breaker allows a call to this provider
      # Returns true if allowed, false if circuit is open
      def circuit_allows?(provider)
        circuit_key = "#{REDIS_PREFIX}:#{provider}:circuit"
        circuit_state = redis.get(circuit_key)

        case circuit_state
        when 'open'
          # Check if cooldown has passed
          tripped_at = redis.get("#{REDIS_PREFIX}:#{provider}:tripped_at")&.to_i || 0
          if Time.now.to_i - tripped_at >= COOLDOWN_PERIOD
            # Allow one test call (half-open state)
            redis.setex(circuit_key, TEST_EXPIRY, 'half_open')
            Rails.logger.info("[Circuit Breaker] #{provider} entering half-open state")
            true
          else
            remaining = COOLDOWN_PERIOD - (Time.now.to_i - tripped_at)
            Rails.logger.warn("[Circuit Breaker] #{provider} circuit open, #{remaining}s until half-open")
            false
          end
        when 'half_open'
          # In half-open, only one call is allowed (already in progress)
          false
        else
          # Closed or not set - allow calls
          true
        end
      rescue Redis::BaseError => e
        Rails.logger.error("[Circuit Breaker] Redis error: #{e.message}, allowing call")
        true # Fail open on Redis error
      end

      # Called after successful call - reset circuit
      def circuit_success(provider)
        circuit_key = "#{REDIS_PREFIX}:#{provider}:circuit"

        redis.multi do |r|
          r.del(circuit_key)
          r.del("#{REDIS_PREFIX}:#{provider}:consecutive_failures")
          r.del("#{REDIS_PREFIX}:#{provider}:tripped_at")
        end

        Rails.logger.info("[Circuit Breaker] #{provider} circuit closed (success)")
      rescue Redis::BaseError => e
        Rails.logger.error("[Circuit Breaker] Redis error on success: #{e.message}")
      end

      # Called after failed call - may trip circuit
      def circuit_failure(provider)
        failures_key = "#{REDIS_PREFIX}:#{provider}:consecutive_failures"
        circuit_key = "#{REDIS_PREFIX}:#{provider}:circuit"

        count = redis.incr(failures_key)
        redis.expire(failures_key, TEST_EXPIRY)

        if count >= FAILURE_THRESHOLD
          redis.multi do |r|
            r.setex(circuit_key, TEST_EXPIRY, 'open')
            r.setex("#{REDIS_PREFIX}:#{provider}:tripped_at", TEST_EXPIRY, Time.now.to_i.to_s)
          end
          Rails.logger.warn("[Circuit Breaker] #{provider} circuit OPEN after #{count} failures")
        end
      rescue Redis::BaseError => e
        Rails.logger.error("[Circuit Breaker] Redis error on failure: #{e.message}")
      end

      # Test all configured providers
      def test_configured_providers
        results = {}

        [:agents, :tasks, :summaries].each do |use_case|
          begin
            provider, _model = Adapters.send(:parse_config_for_use_case, use_case)
            next if results.key?(provider) # Already tested this provider

            if needs_testing?(provider)
              results[provider] = test_provider(provider)
            else
              results[provider] = { skipped: true, reason: 'Recently tested' }
            end
          rescue Adapters::ConfigurationError => e
            Rails.logger.warn("[LLM Connectivity] Skipping #{use_case}: #{e.message}")
          end
        end

        results
      end

      private

      # Generate hash of ENV variables for a provider
      def env_hash_for_provider(provider)
        env_vars = []

        # Collect relevant ENV variables
        [:agents, :tasks, :summaries].each do |use_case|
          env_key = case use_case
                    when :agents then 'LLM_AGENTS_MODEL'
                    when :tasks then 'LLM_TASKS_MODEL'
                    when :summaries then 'LLM_SUMMARIES_MODEL'
                    end

          config = ENV[env_key]
          next unless config

          current_provider, model = config.split(':', 2)
          if current_provider == provider.to_s
            env_vars << "#{env_key}=#{config}"
          end
        end

        # Add API key to hash
        api_key_var = "#{provider.to_s.upcase}_API_KEY"
        api_key = ENV[api_key_var]
        env_vars << "#{api_key_var}=#{api_key[0..10]}" if api_key.present?

        # Return hash of all relevant vars
        Digest::SHA256.hexdigest(env_vars.sort.join('|'))
      end
    end
  end
end
