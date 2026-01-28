# frozen_string_literal: true

FactoryBot.define do
  factory :agent_task do
    title { "Sample Task #{Faker::Number.unique.number(digits: 4)}" }
    instructions { "This is a sample agent task for testing purposes." }
    status { 'active' }
    priority { 'normal' }
    result_summary { nil }
    
    association :goal
    association :user
    
    trait :completed do
      status { 'completed' }
      result_summary { 'Task completed successfully' }
    end
    
    trait :paused do
      status { 'paused' }
      result_summary { 'Task paused by user' }
    end
    
    trait :with_messages do
      after(:create) do |task|
        create(:thread_message, :user_message, agentable: task)
        create(:thread_message, :agent_message, agentable: task)
      end
    end
  end
end
