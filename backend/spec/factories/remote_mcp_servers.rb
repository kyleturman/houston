# frozen_string_literal: true

FactoryBot.define do
  factory :remote_mcp_server do
    sequence(:name) { |n| "test-mcp-server-#{n}" }
    url { "https://api.example.com" }
    auth_type { 'oauth2' }
    metadata { {} }

    # Trait for direct URL servers (no OAuth needed)
    trait :direct do
      url { nil }
      auth_type { 'direct' }
      metadata { { 'user_added' => true } }
    end
  end
end
