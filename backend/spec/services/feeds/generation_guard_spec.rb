# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Feeds::GenerationGuard do
  let(:user) { create(:user) }
  let(:user_agent) { user.user_agent }
  let(:guard) { described_class.new(user) }

  describe '#can_generate?' do
    context 'when user has no active goals' do
      it 'returns blocked result' do
        result = guard.can_generate?('morning')
        expect(result).to be_blocked
        expect(result.reason).to eq('no active goals')
      end
    end

    context 'when user has active goals' do
      let!(:goal) { create(:goal, user: user) }

      it 'allows generation' do
        result = guard.can_generate?('morning')
        expect(result).to be_allowed
      end

      context 'when insights already exist for this period' do
        before do
          create(:feed_insight, user: user, user_agent: user_agent, time_period: 'morning')
        end

        it 'returns blocked result' do
          result = guard.can_generate?('morning')
          expect(result).to be_blocked
          expect(result.reason).to eq('insights already exist')
        end
      end

      context 'when generation is in progress (orchestrator running for feed)' do
        before do
          user_agent.update_runtime_state! do |state|
            state['orchestrator_running'] = true
            state['orchestrator_started_at'] = Time.current.iso8601
            state['current_feed_period'] = 'morning'
          end
        end

        it 'returns blocked result' do
          result = guard.can_generate?('morning')
          expect(result).to be_blocked
          expect(result.reason).to eq('generation in progress')
        end
      end

      context 'when max attempts reached' do
        before do
          described_class::MAX_ATTEMPTS_PER_DAY.times do
            user_agent.record_feed_attempt!('morning')
          end
        end

        it 'returns blocked result' do
          result = guard.can_generate?('morning')
          expect(result).to be_blocked
          expect(result.reason).to include('max attempts')
        end

        it 'allows generation when force=true' do
          result = guard.can_generate?('morning', force: true)
          expect(result).to be_allowed
        end
      end

      context 'when new user created goal after period time' do
        it 'blocks retroactive generation' do
          # Goal was created at 2pm, period was scheduled for 6am
          goal.update_column(:created_at, Time.current.in_time_zone(user.timezone_or_default).change(hour: 14))

          result = guard.can_generate?('morning', scheduled_time: '06:00')
          expect(result).to be_blocked
          expect(result.reason).to include('new user')
        end

        it 'allows generation when no scheduled_time provided' do
          # Without scheduled_time, new-user check is skipped
          goal.update_column(:created_at, Time.current.in_time_zone(user.timezone_or_default).change(hour: 14))

          result = guard.can_generate?('morning')
          expect(result).to be_allowed
        end
      end
    end
  end

  describe '#attempts_today' do
    context 'with no attempts recorded' do
      it 'returns 0' do
        expect(guard.attempts_today('morning')).to eq(0)
      end
    end

    context 'with recent attempts' do
      before do
        user_agent.record_feed_attempt!('morning')
        user_agent.record_feed_attempt!('morning')
      end

      it 'returns the count' do
        expect(guard.attempts_today('morning')).to eq(2)
      end
    end

    context 'with expired attempts (>24 hours old)' do
      before do
        user_agent.record_feed_attempt!('morning')

        # Manually backdate the recorded_at to >24h ago
        user_agent.update_runtime_state! do |state|
          state['feed_attempts']['morning']['recorded_at'] = 25.hours.ago.iso8601
        end
      end

      it 'returns 0 (auto-reset)' do
        expect(guard.attempts_today('morning')).to eq(0)
      end
    end

  end

  describe '#record_attempt!' do
    let!(:goal) { create(:goal, user: user) }

    it 'increments the attempt count' do
      guard.record_attempt!('morning')

      expect(guard.attempts_today('morning')).to eq(1)
    end

    it 'increments on successive calls' do
      guard.record_attempt!('morning')
      guard.record_attempt!('morning')

      expect(guard.attempts_today('morning')).to eq(2)
    end

    it 'tracks periods independently' do
      guard.record_attempt!('morning')
      guard.record_attempt!('afternoon')

      expect(guard.attempts_today('morning')).to eq(1)
      expect(guard.attempts_today('afternoon')).to eq(1)
    end
  end

  describe '#generation_in_progress?' do
    let!(:goal) { create(:goal, user: user) }

    context 'when orchestrator is running with feed period (phase 1)' do
      before do
        user_agent.update_runtime_state! do |state|
          state['orchestrator_running'] = true
          state['orchestrator_started_at'] = Time.current.iso8601
          state['current_feed_period'] = 'morning'
        end
      end

      it 'returns true' do
        expect(guard.generation_in_progress?).to be true
      end
    end

    context 'when orchestrator is running WITHOUT feed period' do
      before do
        user_agent.update_runtime_state! do |state|
          state['orchestrator_running'] = true
          state['orchestrator_started_at'] = Time.current.iso8601
        end
      end

      it 'returns false (not a feed generation run)' do
        expect(guard.generation_in_progress?).to be false
      end
    end

    context 'when active feed task exists (phase 2)' do
      before do
        create(:agent_task,
          user: user,
          taskable: user_agent,
          status: :active,
          context_data: { 'origin_type' => 'feed_generation', 'time_of_day' => 'morning' }
        )
      end

      it 'returns true' do
        expect(guard.generation_in_progress?).to be true
      end
    end

    context 'when no generation is running' do
      it 'returns false' do
        expect(guard.generation_in_progress?).to be false
      end
    end
  end
end
