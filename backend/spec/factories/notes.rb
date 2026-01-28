# frozen_string_literal: true

FactoryBot.define do
  factory :note do
    title { "Sample Note #{Faker::Number.unique.number(digits: 4)}" }
    content { Faker::Lorem.paragraphs(number: 2).join("\n\n") }
    
    association :user
    
    trait :short do
      content { Faker::Lorem.sentence }
    end
    
    trait :long do
      content { Faker::Lorem.paragraphs(number: 5).join("\n\n") }
    end
    
    trait :with_specific_content do
      transient do
        specific_content { nil }
      end
      
      content { specific_content || Faker::Lorem.paragraph }
    end
  end
end
