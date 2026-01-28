# frozen_string_literal: true

module Streams
  module Channels
    module_function

    START = 'start'.freeze
    CHUNK = 'chunk'.freeze
    DONE  = 'done'.freeze
    WELCOME = 'welcome'.freeze

    def for_agentable(agentable:)
      case agentable
      when Goal
        "chat:goal:#{agentable.id}"
      when AgentTask
        "chat:task:#{agentable.id}"
      when UserAgent
        "chat:user_agent:#{agentable.id}"
      else
        raise ArgumentError, "Unknown agentable type: #{agentable.class.name}"
      end
    end

    # Global stream channel for user-wide events
    # Broadcasts: note_created, task_created, goal_updated, etc.
    def global_for_user(user:)
      "global:user:#{user.id}"
    end
  end
end
