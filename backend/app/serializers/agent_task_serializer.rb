# frozen_string_literal: true

class AgentTaskSerializer < ApplicationSerializer
  include ::StringIdAttributes

  set_type :agent_task

  attributes :title, :instructions, :status, :priority,
             :error_type, :error_message, :retry_count, :cancelled_reason,
             :llm_history

  # Convert goal_id to string (JSON:API best practice for mobile clients)
  string_id_attribute :goal_id

  iso8601_timestamp :created_at
  iso8601_timestamp :updated_at
  iso8601_timestamp :next_retry_at
end
