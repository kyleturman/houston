# frozen_string_literal: true

class ThreadMessageSerializer < ApplicationSerializer
  include ::StringIdAttributes

  set_type :thread_message

  attributes :content, :source, :message_type, :metadata

  # Convert IDs to string (JSON:API best practice for mobile clients)
  string_id_attribute :agentable_id
  string_id_attribute :agent_history_id

  iso8601_timestamp :created_at
  iso8601_timestamp :updated_at
end
