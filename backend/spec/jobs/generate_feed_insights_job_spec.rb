# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GenerateFeedInsightsJob, type: :job do
  let(:user) { create(:user) }
  let(:user_agent) { user.user_agent }
  let!(:goal) { create(:goal, user: user, status: :working) }

  before do
    allow(Agents::Orchestrator).to receive(:perform_async)
  end

  describe '#perform' do
    context 'when generation is allowed' do
      it 'triggers orchestrator with feed_generation context' do
        described_class.new.perform(user.id, 'morning')

        expect(Agents::Orchestrator).to have_received(:perform_async).with(
          'UserAgent',
          user_agent.id,
          hash_including(
            'type' => 'feed_generation',
            'time_of_day' => 'morning',
            'scheduled' => true
          )
        )
      end

      it 'records a feed attempt' do
        expect {
          described_class.new.perform(user.id, 'morning')
        }.to change { user_agent.reload.feed_attempt_count('morning') }.from(0).to(1)
      end

      it 'sets feed_period on user_agent' do
        described_class.new.perform(user.id, 'evening')

        expect(user_agent.reload.feed_period).to eq('evening')
      end
    end

    # Guard conditions (insights exist, no goals, max attempts, force) are
    # tested in spec/services/feeds/generation_guard_spec.rb

    context 'when period is disabled' do
      before do
        user_agent.update_runtime_state! do |state|
          state['feed_schedule'] = {
            'enabled' => true,
            'periods' => {
              'morning' => { 'enabled' => false, 'time' => '06:00' },
              'afternoon' => { 'enabled' => true, 'time' => '12:00' },
              'evening' => { 'enabled' => true, 'time' => '17:00' }
            },
            'jobs' => {}
          }
        end
      end

      it 'does not trigger orchestrator' do
        described_class.new.perform(user.id, 'morning')

        expect(Agents::Orchestrator).not_to have_received(:perform_async)
      end
    end

    context 'when user does not exist' do
      it 'returns without error' do
        expect {
          described_class.new.perform(99999, 'morning')
        }.not_to raise_error

        expect(Agents::Orchestrator).not_to have_received(:perform_async)
      end
    end
  end
end
