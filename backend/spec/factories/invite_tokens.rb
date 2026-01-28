# frozen_string_literal: true

FactoryBot.define do
  factory :invite_token do
    user
    expires_at { 7.days.from_now }

    after(:build) do |invite_token|
      invite_token.set_token!
    end

    trait :never_expires do
      expires_at { nil }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :used do
      first_used_at { 1.hour.ago }
    end

    trait :locked do
      first_used_at { 25.hours.ago }
    end

    trait :revoked do
      revoked_at { 1.hour.ago }
    end
  end
end
