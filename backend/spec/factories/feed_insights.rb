# frozen_string_literal: true

FactoryBot.define do
  factory :feed_insight do
    association :user
    association :user_agent

    insight_type { :reflection }
    goal_ids { [] }
    metadata { { 'prompt' => 'How are your goals going?' } }

    trait :reflection do
      insight_type { :reflection }
      metadata { { 'prompt' => 'How are your goals going?', 'insight_type' => 'engagement_check' } }
    end

    trait :discovery do
      insight_type { :discovery }
      metadata do
        {
          'title' => 'New Study on Productivity',
          'summary' => 'Researchers found that...',
          'url' => 'https://example.com/study',
          'source' => 'example.com',
          'discovery_type' => 'article'
        }
      end
    end
  end
end
