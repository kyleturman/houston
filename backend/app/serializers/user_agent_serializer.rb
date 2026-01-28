# frozen_string_literal: true

class UserAgentSerializer < ApplicationSerializer
  set_type :user_agent

  attributes :learnings

  iso8601_timestamp :created_at
  iso8601_timestamp :updated_at
end
