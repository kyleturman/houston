# frozen_string_literal: true

FactoryBot.define do
  factory :goal do
    user
    sequence(:title) { |n| "Goal #{n}" }
    description { 'A test goal for development' }
    status { :waiting }
  end
end
