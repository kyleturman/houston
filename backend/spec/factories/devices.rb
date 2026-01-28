# frozen_string_literal: true

FactoryBot.define do
  factory :device do
    user
    name { "Test Device" }
    platform { "iOS" }
    token_id { SecureRandom.hex(8) }
    token_digest { BCrypt::Password.create(SecureRandom.hex(32)) }
    metadata { {} }

    # Hook to set raw token after creation for testing
    after(:build) do |device|
      device.set_token!
    end
  end
end
