# frozen_string_literal: true

FactoryBot.define do
  factory :user_agent do
    association :user

    llm_history { [] }
    learnings { [] }
    runtime_state { {} }
  end
end
