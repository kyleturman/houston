# frozen_string_literal: true

FactoryBot.define do
  factory :thread_message do
    content { Faker::Lorem.sentence }
    source { 'user' }
    
    association :user
    association :agentable, factory: :goal
    
    trait :user_message do
      source { 'user' }
      content { "User message: #{Faker::Lorem.sentence}" }
    end
    
    trait :agent_message do
      source { 'agent' }
      content { "Agent response: #{Faker::Lorem.sentence}" }
    end
    
    trait :system_message do
      source { 'error' }
      content { "System notification: #{Faker::Lorem.sentence}" }
    end
    
    trait :for_goal do
      association :agentable, factory: :goal
    end
    
    trait :for_task do
      association :agentable, factory: :agent_task
    end
    
    trait :with_tool_activity do
      source { 'agent' }
      message_type { 'tool' }
      metadata do
        {
          tool_activity: {
            id: SecureRandom.uuid,
            name: 'create_note',
            status: 'success',
            input: {
              title: 'Sample Note',
              content: 'Sample note content'
            },
            display_message: 'Jotting down findings',
            data: {
              note_id: rand(1..1000),
              title: 'Sample Note',
              content: 'Sample note content',
              status: 'created'
            }
          }
        }
      end
    end
  end
end
