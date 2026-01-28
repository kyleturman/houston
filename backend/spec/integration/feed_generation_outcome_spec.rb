# frozen_string_literal: true

require 'rails_helper'

# Tests that feed generation produces actual FeedInsight records.
# Validates the generate_feed_insights tool and the job→orchestrator→tool pipeline.
RSpec.describe 'Feed generation outcome', :integration do
  let(:user) { create(:user) }
  let(:user_agent) { user.user_agent }
  let!(:goal) { create(:goal, user: user, status: :working) }

  describe 'GenerateFeedInsights tool' do
    let(:tool) do
      Tools::System::GenerateFeedInsights.new(
        user: user,
        agentable: task,
        context: { 'time_of_day' => 'morning', 'feed_period' => 'morning' }
      )
    end

    context 'when called from a standalone task (UserAgent taskable)' do
      let(:task) do
        AgentTask.create!(
          user: user,
          taskable: user_agent,
          title: 'Jan 27, morning insights',
          instructions: 'Generate morning feed insights',
          status: :active,
          context_data: { 'origin_type' => 'feed_generation', 'time_of_day' => 'morning' }
        )
      end

      it 'creates FeedInsight records with correct attributes' do
        result = tool.execute(
          reflections: [
            { 'prompt' => 'How is your fitness goal going?', 'goal_ids' => [goal.id.to_s] }
          ],
          discoveries: [
            { 'title' => 'New workout routine', 'summary' => 'A study on HIIT', 'url' => 'https://example.com/hiit', 'goal_ids' => [goal.id.to_s] }
          ]
        )

        expect(result[:success]).to be true
        expect(result[:reflection_count]).to eq(1)
        expect(result[:discovery_count]).to eq(1)

        insights = FeedInsight.where(user: user)
        expect(insights.count).to eq(2)
        expect(insights.where(insight_type: :reflection).count).to eq(1)
        expect(insights.where(insight_type: :discovery).count).to eq(1)
        expect(insights.pluck(:time_period).uniq).to eq(['morning'])
      end

      it 'assigns goal_ids correctly' do
        tool.execute(
          reflections: [{ 'prompt' => 'Test', 'goal_ids' => [goal.id.to_s] }],
          discoveries: []
        )

        insight = FeedInsight.last
        expect(insight.goal_ids).to eq([goal.id])
      end
    end

    context 'when called from a goal task (wrong context)' do
      let(:task) do
        AgentTask.create!(
          user: user,
          taskable: goal,
          title: 'Some goal task',
          instructions: 'Do something',
          status: :active
        )
      end

      it 'returns an error and creates no insights' do
        result = tool.execute(
          reflections: [{ 'prompt' => 'Test' }],
          discoveries: []
        )

        expect(result[:success]).to be false
        expect(FeedInsight.where(user: user).count).to eq(0)
      end
    end
  end

  # Job→orchestrator context and guard behavior tested in:
  # - spec/jobs/generate_feed_insights_job_spec.rb
  # - spec/services/feeds/generation_guard_spec.rb
end
