# frozen_string_literal: true

class NoteSerializer < ApplicationSerializer
  include ::StringIdAttributes

  set_type :note

  attributes :title, :content, :metadata, :source

  # Convert goal_id to string (JSON:API best practice for mobile clients)
  string_id_attribute :goal_id

  iso8601_timestamp :created_at
  iso8601_timestamp :updated_at
end
