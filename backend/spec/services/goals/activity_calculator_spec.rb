# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Goals::ActivityCalculator do
  include_context 'authenticated user with goal'
  include ActiveSupport::Testing::TimeHelpers

  describe '#calculate' do
    subject(:result) { described_class.new(goal).calculate }

    context 'with no activity' do
      it 'returns low activity level' do
        expect(result[:level]).to eq(:low)
        expect(result[:score]).to eq(0.0)
        expect(result[:details][:notes]).to eq(0)
        expect(result[:details][:messages]).to eq(0)
      end
    end

    context 'with only user notes' do
      before do
        create(:note, goal: goal, user: user, source: :user)
      end

      it 'counts notes with 1.5x weight' do
        expect(result[:score]).to eq(1.5)
        expect(result[:level]).to eq(:low) # 1.5 < 2 moderate threshold
      end
    end

    context 'with notes and messages reaching moderate threshold' do
      before do
        create(:note, goal: goal, user: user, source: :user)
        create(:thread_message, agentable: goal, user: user, source: :user)
      end

      it 'returns moderate activity level' do
        # 1 note * 1.5 + 1 message = 2.5 >= 2 (moderate threshold)
        expect(result[:level]).to eq(:moderate)
        expect(result[:score]).to eq(2.5)
      end
    end

    context 'with high activity' do
      before do
        3.times { create(:note, goal: goal, user: user, source: :user) }
        2.times { create(:thread_message, agentable: goal, user: user, source: :user) }
      end

      it 'returns high activity level' do
        # 3 notes * 1.5 + 2 messages = 6.5 >= 5 (high threshold)
        expect(result[:level]).to eq(:high)
        expect(result[:score]).to eq(6.5)
      end
    end

    context 'with old notes outside window' do
      before do
        travel_to 10.days.ago do
          create(:note, goal: goal, user: user, source: :user)
        end
      end

      it 'excludes old notes from count' do
        expect(result[:score]).to eq(0.0)
        expect(result[:level]).to eq(:low)
      end
    end

    context 'with agent notes' do
      before do
        create(:note, goal: goal, user: user, source: :agent)
      end

      it 'excludes agent notes from count' do
        expect(result[:score]).to eq(0.0)
        expect(result[:level]).to eq(:low)
      end
    end

    context 'with import notes' do
      before do
        create(:note, goal: goal, user: user, source: :import)
      end

      it 'includes import notes in count' do
        expect(result[:score]).to eq(1.5)
      end
    end

    context 'with messages from non-user sources' do
      before do
        create(:thread_message, agentable: goal, user: user, source: :agent)
      end

      it 'excludes non-user messages from count' do
        expect(result[:score]).to eq(0.0)
      end
    end
  end

  describe '#level' do
    it 'returns just the level symbol' do
      calculator = described_class.new(goal)
      expect(calculator.level).to eq(:low)
    end
  end
end
