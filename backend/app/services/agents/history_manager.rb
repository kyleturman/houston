# frozen_string_literal: true

module Agents
  # Centralized LLM history management
  # CRITICAL: Always use string keys for JSON storage compatibility
  class HistoryManager
    class << self
      # Add a history entry with proper format
      def add_entry(agentable:, role:, content:)
        agentable.add_to_llm_history({
          'role' => role,
          'content' => content,
          'timestamp' => Time.current.iso8601
        })
      end

      # Convenience methods for common operations
      def add_user_message(agentable:, content:)
        add_entry(agentable: agentable, role: 'user', content: content)
      end

      def add_assistant_message(agentable:, content:)
        add_entry(agentable: agentable, role: 'assistant', content: content)
      end

      # Get history for API calls
      def get_messages(agentable)
        history = agentable.get_llm_history
        # Convert to format expected by LLM APIs (symbol keys for in-memory use)
        messages = Array(history).map { |h| { role: h['role'], content: h['content'] } }

        # Validate role alternation in development/test to catch bugs early
        validate_role_alternation(messages, agentable) if Rails.env.development? || Rails.env.test?

        messages
      end

      private

      # Validate that roles strictly alternate between user and assistant
      # Logs warning in development/test to help catch bugs early
      def validate_role_alternation(messages, agentable)
        return if messages.empty?

        messages.each_cons(2) do |msg1, msg2|
          if msg1[:role] == msg2[:role]
            warning = "[HistoryManager] INVALID HISTORY: Consecutive #{msg1[:role]} messages detected in #{agentable.class.name}##{agentable.id}"
            Rails.logger.warn(warning)
            puts "⚠️  #{warning}"
            puts "   Message 1: #{msg1[:content].to_s[0..100]}"
            puts "   Message 2: #{msg2[:content].to_s[0..100]}"
            break # Only warn once
          end
        end
      end
    end
  end
end
