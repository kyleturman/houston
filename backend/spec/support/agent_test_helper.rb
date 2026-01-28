# frozen_string_literal: true

# Helper for testing agent execution with proper timeout and debugging
# Use this when you need to run actual orchestrator/CoreLoop in tests
module AgentTestHelper
  # Execute an agent task with timeout and detailed progress tracking
  # This helps diagnose hanging tests by showing exactly where execution stops
  #
  # Usage:
  #   run_agent_with_timeout(goal) do
  #     goal.update_llm_history!(...)
  #     Orchestrator.perform_async(...)
  #   end
  #
  def run_agent_with_timeout(agentable, timeout: 10.seconds, &block)
    puts "\n🤖 [AgentTest] Starting agent execution for #{agentable.class.name}##{agentable.id}"
    puts "   Timeout: #{timeout}s"
    
    start_time = Time.current
    progress_thread = start_progress_monitor(agentable, start_time, timeout)
    
    begin
      # Use Timeout to enforce hard limit
      Timeout.timeout(timeout) do
        block.call
      end
      
      puts "✅ [AgentTest] Agent completed in #{(Time.current - start_time).round(2)}s"
    rescue Timeout::Error
      print_debug_state(agentable, start_time)
      raise "Agent execution timed out after #{timeout}s. See debug output above."
    ensure
      progress_thread&.kill
    end
  end
  
  # Monitor progress in background thread and print periodic updates
  def start_progress_monitor(agentable, start_time, timeout)
    Thread.new do
      loop do
        sleep 1
        elapsed = Time.current - start_time
        
        # Print progress every 2 seconds
        if elapsed.to_i % 2 == 0
          llm_calls = agentable.llm_history.count
          messages = agentable.thread_messages.count
          
          puts "   [#{elapsed.round(1)}s] LLM calls: #{llm_calls}, Messages: #{messages}"
          
          # Warning if getting close to timeout
          if elapsed > timeout * 0.8
            puts "   ⚠️  Warning: #{(timeout - elapsed).round(1)}s until timeout"
          end
        end
      end
    rescue => e
      # Thread killed, ignore
    end
  end
  
  # Print detailed state when test times out
  def print_debug_state(agentable, start_time)
    puts "\n❌ [AgentTest] TIMEOUT - Debug State:"
    puts "   Duration: #{(Time.current - start_time).round(2)}s"
    puts "   Type: #{agentable.class.name}"
    puts "   ID: #{agentable.id}"
    
    if agentable.respond_to?(:status)
      puts "   Status: #{agentable.status}"
    end
    
    puts "   LLM History entries: #{agentable.llm_history.count}"
    puts "   Thread Messages: #{agentable.thread_messages.count}"
    
    # Show last few LLM history entries
    if agentable.llm_history.any?
      puts "\n   Last 3 LLM history entries:"
      agentable.llm_history.last(3).each_with_index do |entry, i|
        puts "     #{i + 1}. #{entry['role']}: #{entry['content']&.to_s&.truncate(80)}"
      end
    end
    
    # Check for infinite loops (same tool called many times)
    if agentable.llm_history.count > 10
      tool_calls = agentable.llm_history
        .select { |e| e['role'] == 'assistant' && e['tool_calls'].present? }
        .flat_map { |e| e['tool_calls'].map { |tc| tc['name'] } }
      
      tool_counts = tool_calls.tally
      if tool_counts.any? { |_tool, count| count > 5 }
        puts "\n   ⚠️  Possible infinite loop detected:"
        tool_counts.sort_by { |_tool, count| -count }.first(3).each do |tool, count|
          puts "      #{tool}: called #{count} times"
        end
      end
    end
    
    puts "\n   💡 Tip: Check if Service.agent_call is properly mocked or if CoreLoop is stuck"
  end
  
  # Wait for agentable to reach a certain state with timeout
  # Useful for waiting for status changes, message creation, etc.
  #
  # Usage:
  #   wait_for_state(goal, timeout: 5) { goal.reload.waiting? }
  #
  def wait_for_state(agentable, timeout: 10.seconds, check_interval: 0.1.seconds, &condition)
    start_time = Time.current
    
    loop do
      return true if condition.call
      
      elapsed = Time.current - start_time
      if elapsed > timeout
        puts "\n❌ [AgentTest] wait_for_state timed out after #{elapsed.round(2)}s"
        print_debug_state(agentable, start_time)
        raise "State condition not met within #{timeout}s"
      end
      
      sleep check_interval
    end
  end
end

RSpec.configure do |config|
  config.include AgentTestHelper
end
