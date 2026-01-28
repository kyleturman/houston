# frozen_string_literal: true

class AgentActivitySerializer < ApplicationSerializer
  include ::StringIdAttributes

  set_type :agent_activity

  attributes :agent_type,
             :input_tokens,
             :output_tokens,
             :cost_cents,
             :tool_count,
             :iterations,
             :natural_completion

  # Polymorphic agentable references
  string_id_attribute :agentable_id
  attribute :agentable_type

  # Optional goal reference
  string_id_attribute :goal_id

  # Tools usage
  attribute :tools_called
  attribute :tools_summary do |object|
    object.tools_summary
  end

  # Calculated fields
  attribute :duration_seconds do |object|
    object.duration_seconds
  end

  attribute :cost_dollars do |object|
    object.cost_dollars
  end

  attribute :formatted_cost do |object|
    object.formatted_cost
  end

  attribute :total_tokens do |object|
    object.total_tokens
  end

  attribute :agent_type_label do |object|
    object.agent_type_label
  end

  # Timestamps
  iso8601_timestamp :started_at
  iso8601_timestamp :completed_at
  iso8601_timestamp :created_at
  iso8601_timestamp :updated_at
end
