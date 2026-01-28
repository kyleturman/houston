# frozen_string_literal: true

class AgentHistorySerializer < ApplicationSerializer
  include ::StringIdAttributes

  set_type :agent_history

  attributes :summary, :completion_reason, :message_count, :token_count, :agentable_type

  string_id_attribute :agentable_id

  iso8601_timestamp :started_at
  iso8601_timestamp :completed_at
  iso8601_timestamp :created_at
  iso8601_timestamp :updated_at
end
