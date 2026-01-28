# frozen_string_literal: true

# Test LLM provider connectivity on server start
# Only tests if never tested before or ENV variables changed
# Uses minimal tokens to keep costs near zero

Rails.application.config.after_initialize do
  # Skip in rake tasks (db:migrate, etc) and test environment
  next if defined?(Rails::Console) || defined?(Rake) || Rails.env.test?

  # Run in background thread so server starts immediately
  Thread.new do
    begin
      sleep 2 # Give server a moment to fully start

      Rails.logger.info("[LLM Connectivity] Checking provider connectivity...")
      results = Llms::ConnectivityTracker.test_configured_providers

      if results.any?
        tested = results.count { |_, r| !r[:skipped] }
        skipped = results.count { |_, r| r[:skipped] }
        healthy = results.count { |_, r| r[:success] }
        unhealthy = tested - healthy

        Rails.logger.info("[LLM Connectivity] Results: #{healthy}/#{tested} healthy, #{skipped} skipped (recently tested)")

        if unhealthy > 0
          Rails.logger.warn("[LLM Connectivity] ⚠️  #{unhealthy} provider(s) failed connectivity test")
          results.each do |provider, result|
            if result[:success] == false
              Rails.logger.warn("[LLM Connectivity]   ✗ #{provider}: #{result[:error]}")
            end
          end
        end
      else
        Rails.logger.info("[LLM Connectivity] No providers configured for testing")
      end
    rescue => e
      Rails.logger.error("[LLM Connectivity] Failed to run startup tests: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
    end
  end
end
