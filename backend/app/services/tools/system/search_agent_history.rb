# frozen_string_literal: true

module Tools
  module System
    class SearchAgentHistory < BaseTool
      # Tool metadata for planning and orchestration
      def self.metadata
        super.merge(
          name: 'search_agent_history',
          description: 'Search your previous conversation history for specific information. Use when you need context from past interactions beyond the recent summaries provided. Searches both summaries and full conversation content. [Silent - returns data to you, user won\'t see this]',
          params_hint: 'query (required): What to search for. timeframe (optional): "last_week", "last_month", "last_year"'
        )
      end

      # JSON Schema for tool parameters
      def self.schema
        {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'Search query - searches summaries and conversation content'
            },
            timeframe: {
              type: 'string',
              enum: ['last_week', 'last_month', 'last_year'],
              description: 'Optional time constraint for search'
            }
          },
          required: ['query'],
          additionalProperties: false
        }
      end

      # Search agent history
      # Params:
      # - query: String (required) - what to search for
      # - timeframe: String (optional) - time constraint
      # Returns: { success: true, observation: String }
      def execute(query:, timeframe: nil)
        # Emit progress update
        emit_tool_progress("Searching conversation history...", data: {
          query: query,
          timeframe: timeframe,
          status: 'searching'
        })

        time_constraint = parse_timeframe(timeframe)

        # Search summary first (encrypted agent_history can't be searched in SQL)
        # We'll check full history in Ruby after decryption
        base_results = @agentable.agent_histories
          .where(time_constraint ? "completed_at >= ?" : "1=1", time_constraint)
          .order(completed_at: :desc)
          .select(:id, :summary, :completed_at, :message_count, :agent_history)

        # Filter results: check summary in SQL and full history in Ruby
        # Handle decryption errors gracefully by skipping corrupted records
        results = []
        base_results.each do |history|
          break if results.length >= 5
          begin
            summary = history.summary
            agent_hist = history.agent_history
            if summary&.downcase&.include?(query.downcase) ||
               agent_hist.to_s.downcase.include?(query.downcase)
              results << history
            end
          rescue ActiveRecord::Encryption::Errors::Decryption
            # Skip corrupted records
            next
          end
        end

        if results.empty?
          observation = no_results_message(query, timeframe)

          emit_tool_completion("No results found", data: {
            query: query,
            result_count: 0
          })

          return {
            success: true,
            observation: observation
          }
        end

        formatted = format_search_results(results, query)
        observation = <<~RESULT
          Found #{results.length} previous session(s) matching '#{query}':

          #{formatted}
        RESULT

        # Emit completion update
        emit_tool_completion("Found #{results.length} session(s)", data: {
          query: query,
          result_count: results.length
        })

        {
          success: true,
          observation: observation
        }
      end

      private

      def parse_timeframe(timeframe)
        case timeframe
        when 'last_week' then 1.week.ago
        when 'last_month' then 1.month.ago
        when 'last_year' then 1.year.ago
        else nil
        end
      end

      def no_results_message(query, timeframe)
        timeframe_text = timeframe ? " in #{timeframe}" : ""
        "No previous sessions found matching '#{query}'#{timeframe_text}."
      end

      def format_search_results(results, query)
        results.filter_map do |result|
          begin
            summary = result.summary
            agent_hist = result.agent_history
            # Check if query matched ONLY in full history (not in summary)
            matched_in_summary = summary&.downcase&.include?(query.downcase)
            matched_in_history = agent_hist.to_s.downcase.include?(query.downcase)
            marker = (matched_in_history && !matched_in_summary) ? " [matched in conversation]" : ""

            <<~RESULT.strip
              • #{result.completed_at.strftime('%b %d, %Y')}: #{summary} (#{result.message_count} messages)#{marker}
            RESULT
          rescue ActiveRecord::Encryption::Errors::Decryption
            # Skip corrupted records
            nil
          end
        end.join("\n")
      end
    end
  end
end
