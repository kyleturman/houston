# frozen_string_literal: true

class GoalSerializer < ApplicationSerializer
  set_type :goal

  attributes :title, :description, :status, :accent_color, :agent_instructions, :enabled_mcp_servers, :learnings, :llm_history, :runtime_state, :display_order, :activity_level, :notes_count, :tasks_count, :check_in_schedule, :active_mcp_servers_count

  iso8601_timestamp :created_at
  iso8601_timestamp :updated_at

  # Activity level based on recent notes and messages
  # Returns :high, :moderate, or :low
  attribute :activity_level do |goal|
    Goals::ActivityCalculator.new(goal).calculate[:level]
  end

  # Total notes count for this goal
  attribute :notes_count do |goal|
    goal.notes.count
  end

  # Total tasks count for this goal
  attribute :tasks_count do |goal|
    goal.agent_tasks.count
  end

  # Count of MCP servers that are both enabled for this goal AND currently available
  # This filters out servers that have been disconnected or disabled since the goal was created
  attribute :active_mcp_servers_count do |goal|
    enabled = goal.enabled_mcp_servers || []
    next 0 if enabled.empty?

    # Get all currently available server names (healthy local servers)
    available_servers = McpServer.where(healthy: true).pluck(:name).map(&:downcase)

    # Count how many of the goal's enabled servers are actually available
    enabled.count { |server_name| available_servers.include?(server_name.downcase) }
  end
end
