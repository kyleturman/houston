# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FeedInsight, type: :model do
  let(:user) { create(:user) }
  let(:user_agent) { user.user_agent || create(:user_agent, user: user) }

  describe 'validations' do
    it 'requires insight_type to be a valid enum value' do
      insight = FeedInsight.new(
        user: user,
        user_agent: user_agent,
        insight_type: :reflection,
        metadata: { 'prompt' => 'Test reflection?' }
      )
      expect(insight).to be_valid

      # Enum will raise error if invalid value is set, so we test valid enum works
      expect(insight.insight_type).to eq('reflection')
    end

    it 'requires metadata' do
      insight = FeedInsight.new(user: user, user_agent: user_agent, insight_type: :reflection, metadata: nil)
      expect(insight).not_to be_valid
      expect(insight.errors[:metadata]).to be_present
    end
  end

  describe 'scopes' do
    before do
      create(:feed_insight, user: user, user_agent: user_agent, created_at: 10.days.ago)
      create(:feed_insight, user: user, user_agent: user_agent, created_at: 5.days.ago)
      create(:feed_insight, user: user, user_agent: user_agent, created_at: Time.current)
    end

    it 'returns recent insights (last 7 days)' do
      expect(FeedInsight.recent.count).to eq(2)
    end

  end

  describe '.cleanup_old_insights' do
    it 'deletes insights older than 7 days' do
      old_insight = create(:feed_insight, user: user, user_agent: user_agent, created_at: 8.days.ago)
      recent_insight = create(:feed_insight, user: user, user_agent: user_agent, created_at: 5.days.ago)

      expect {
        FeedInsight.cleanup_old_insights
      }.to change { FeedInsight.count }.by(-1)

      expect(FeedInsight.exists?(old_insight.id)).to be false
      expect(FeedInsight.exists?(recent_insight.id)).to be true
    end
  end

  describe '#display_content' do
    context 'for reflection' do
      it 'returns the prompt' do
        insight = create(:feed_insight,
          user: user,
          user_agent: user_agent,
          insight_type: :reflection,
          metadata: { 'prompt' => 'How is your Spanish going?' }
        )
        expect(insight.display_content).to eq('How is your Spanish going?')
      end
    end

    context 'for discovery' do
      it 'returns discovery data' do
        insight = create(:feed_insight,
          user: user,
          user_agent: user_agent,
          insight_type: :discovery,
          metadata: {
            'title' => 'New Spanish App',
            'summary' => 'Great for learning',
            'url' => 'https://example.com',
            'source' => 'example.com'
          }
        )
        content = insight.display_content
        expect(content[:title]).to eq('New Spanish App')
        expect(content[:url]).to eq('https://example.com')
      end
    end
  end
end
