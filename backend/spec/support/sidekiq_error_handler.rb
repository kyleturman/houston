# frozen_string_literal: true

# Sidekiq error handler for tests - makes background job errors visible
# 
# In Sidekiq inline testing mode, errors are caught but not re-raised.
# This helper monkey-patches Sidekiq::Testing to make errors visible and fail tests.

module SidekiqTestingErrorHandler
  def process_job(worker, job)
    super
  rescue => e
    # Print error details to test output
    puts "\n" + "="*80
    puts "❌ SIDEKIQ JOB ERROR DETECTED"
    puts "="*80
    puts "Exception: #{e.class}: #{e.message}"
    puts "Worker: #{worker.class}"
    puts "Job: #{job.inspect}"
    puts "\nBacktrace:"
    puts e.backtrace.first(15).map { |line| "  #{line}" }.join("\n")
    puts "="*80 + "\n"
    
    # Re-raise to fail the test
    raise e
  end
end

# Only apply in test environment
if defined?(Sidekiq::Testing)
  Sidekiq::Testing.singleton_class.prepend(SidekiqTestingErrorHandler)
end
