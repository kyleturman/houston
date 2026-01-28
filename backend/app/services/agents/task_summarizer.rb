# frozen_string_literal: true

module Agents
  # Extracts task completion summaries for reporting back to goal agents.
  #
  # PRIMARY: Uses the agent's final text message - agents naturally explain
  # what they accomplished, and we guide them to include key IDs.
  #
  # FALLBACK: If no final text, extracts basic info from the last tool result
  # using generic field names (id, name).
  #
  class TaskSummarizer
    def initialize(task)
      @task = task
      @history = task.get_llm_history || []
    rescue => e
      Rails.logger.warn("[TaskSummarizer] Failed to load history for task #{task.id}: #{e.message}")
      @history = []
    end

    # Generate summary of what the task accomplished
    def summarize
      # Primary: agent's final text message
      final_text = extract_final_text
      return final_text if final_text.present?

      # Fallback: extract from last tool result
      extract_from_last_tool_result || "Task completed"
    rescue => e
      Rails.logger.warn("[TaskSummarizer] Failed to summarize task #{@task.id}: #{e.message}")
      "Task completed"
    end

    private

    # Extract the agent's final text message (what it said after finishing work)
    def extract_final_text
      # Walk backwards through history to find last assistant message with text
      @history.reverse_each do |entry|
        next unless entry['role'] == 'assistant'

        content = entry['content']
        next unless content.is_a?(Array)

        # Look for text blocks (not tool_use)
        text_parts = content.select { |c| c.is_a?(Hash) && c['type'] == 'text' }
        next if text_parts.empty?

        # Combine text parts and clean up
        text = text_parts.map { |t| t['text'] }.join("\n").strip
        return text.truncate(500) if text.present?
      end

      nil
    end

    # Fallback: extract basic info from the last successful tool result
    def extract_from_last_tool_result
      last_result = find_last_tool_result
      return nil unless last_result

      parsed = parse_json(last_result)
      return nil unless parsed.is_a?(Hash)

      # Just look for the most common fields: id and name
      name = parsed['name'] || parsed['title']
      id = parsed['id']

      if name && id
        "Created '#{name}' (ID: #{id})"
      elsif name
        "Created '#{name}'"
      elsif id
        "Completed (ID: #{id})"
      else
        nil
      end
    end

    def find_last_tool_result
      @history.reverse_each do |entry|
        next unless entry['role'] == 'user'

        content = entry['content']
        next unless content.is_a?(Array)

        content.reverse_each do |item|
          next unless item.is_a?(Hash) && item['type'] == 'tool_result'
          next if item['is_error']

          return item['content'] if item['content'].present?
        end
      end

      nil
    end

    def parse_json(content)
      return content if content.is_a?(Hash)
      return nil unless content.is_a?(String) && content.include?('{')

      # Find and parse JSON in the string
      json_match = content.match(/\{[^{}]*\}/m)
      JSON.parse(json_match[0]) if json_match
    rescue JSON::ParserError
      nil
    end
  end
end
