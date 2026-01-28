# frozen_string_literal: true

module Tools
  module System
    # Tool for searching through user's notes when agents need specific information
    class SearchNotes < BaseTool
      def self.metadata
        {
          name: 'search_notes',
          description: 'Search through ALL notes for this goal when you need specific information not in the recent notes summary. Use for finding older notes or specific details. Returns up to 8 notes with 300 characters each. For NEW information or research, use web search instead. [Silent - returns data to you, user won\'t see this]',
          params_hint: 'query (required): search terms to find relevant notes'
        }
      end

      # JSON Schema for tool parameters
      def self.schema
        {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'Search terms to find relevant notes' }
          },
          required: ['query'],
          additionalProperties: false
        }
      end

      def execute(query:)
        return { success: false, error: 'Query is required' } if query.blank?
        return { success: false, error: 'No goal context available' } unless @goal

        begin
          # Search notes using Note model's search method
          notes = Note.search_for_goal(goal: @goal, query: query, limit: 8)

          if notes.empty?
            return {
              success: true,
              observation: "No notes found matching '#{query}'. You may need to ask the user for this information."
            }
          end

          # Build detailed results for the search
          results = notes.map do |note|
            date = note.created_at&.to_date&.iso8601 || ""
            content_preview = note.content.to_s.strip
            # Truncate very long notes but keep more detail than the summary
            if content_preview.length > 300
              content_preview = content_preview[0, 300] + "..."
            end

            "Note ##{note.id} (#{date}):\n#{content_preview}"
          end

          search_results = results.join("\n\n")
          {
            success: true,
            observation: "Found #{notes.count} relevant notes:\n\n#{search_results}"
          }

        rescue => e
          Rails.logger.error("[SearchNotes] Error: #{e.message}")
          Rails.logger.error(e.backtrace.first(5).join("\n"))
          { success: false, error: "Search failed: #{e.message}" }
        end
      end
    end
  end
end
