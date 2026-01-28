# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentCheckInJob, type: :job do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }

  describe '#perform' do
    let(:check_in_data) do
      {
        'intent' => 'Review progress',
        'created_at' => 3.days.ago.iso8601
      }
    end

    context 'with follow_up check-in' do
      before do
        state = goal.runtime_state || {}
        state['next_follow_up'] = {
          'job_id' => 'test-job-123',
          'scheduled_for' => 3.days.from_now.iso8601,
          'intent' => 'Review progress'
        }
        goal.update_column(:runtime_state, state)
      end

      it 'triggers orchestrator with check-in context' do
        allow(Agents::Orchestrator).to receive(:perform_async)

        described_class.new.perform(
          'Goal',
          goal.id,
          'follow_up',
          check_in_data
        )

        expect(Agents::Orchestrator).to have_received(:perform_async).with(
          'Goal',
          goal.id,
          hash_including('type' => 'agent_check_in')
        )
      end

      it 'removes follow_up from runtime_state when it fires' do
        allow(Agents::Orchestrator).to receive(:perform_async)

        described_class.new.perform(
          'Goal',
          goal.id,
          'follow_up',
          check_in_data
        )

        expect(goal.reload.next_follow_up).to be_nil
      end

      it 'handles legacy short_term slot' do
        allow(Agents::Orchestrator).to receive(:perform_async)

        described_class.new.perform(
          'Goal',
          goal.id,
          'short_term',  # Legacy slot name
          check_in_data
        )

        # Should still remove follow_up (short_term normalizes to follow_up)
        expect(goal.reload.next_follow_up).to be_nil
      end

      it 'clears original_follow_up when follow-up check-in fires' do
        allow(Agents::Orchestrator).to receive(:perform_async)

        # Set up original_follow_up (as if NoteTriggeredCheckInJob stored it)
        state = goal.runtime_state || {}
        state['original_follow_up'] = {
          'scheduled_for' => 3.days.from_now.iso8601,
          'intent' => 'Original intent',
          'stored_at' => Time.current.iso8601
        }
        goal.update_column(:runtime_state, state)

        described_class.new.perform(
          'Goal',
          goal.id,
          'follow_up',
          check_in_data
        )

        expect(goal.reload.runtime_state['original_follow_up']).to be_nil
      end
    end

    context 'with scheduled check-in' do
      before do
        goal.update!(check_in_schedule: {
          'frequency' => 'daily',
          'time' => '09:00',
          'intent' => 'Daily review'
        })
        state = goal.runtime_state || {}
        state['scheduled_check_in'] = {
          'job_id' => 'test-job-456',
          'scheduled_for' => Time.current.iso8601,
          'intent' => 'Daily review'
        }
        goal.update_column(:runtime_state, state)
      end

      it 'removes scheduled_check_in from runtime_state' do
        allow(Agents::Orchestrator).to receive(:perform_async)
        allow_any_instance_of(Goals::ScheduleCalculator).to receive(:schedule_next_check_in!)

        described_class.new.perform(
          'Goal',
          goal.id,
          'scheduled',
          { 'intent' => 'Daily review' }
        )

        expect(goal.reload.runtime_state['scheduled_check_in']).to be_nil
      end

      it 'schedules next occurrence for recurring check-ins' do
        allow(Agents::Orchestrator).to receive(:perform_async)
        calculator = instance_double(Goals::ScheduleCalculator)
        allow(Goals::ScheduleCalculator).to receive(:new).with(goal).and_return(calculator)
        expect(calculator).to receive(:schedule_next_check_in!)

        described_class.new.perform(
          'Goal',
          goal.id,
          'scheduled',
          { 'intent' => 'Daily review' }
        )
      end
    end

    context 'with multiple check-in types' do
      before do
        state = goal.runtime_state || {}
        state['next_follow_up'] = {
          'job_id' => 'follow-up-job',
          'scheduled_for' => 3.days.from_now.iso8601,
          'intent' => 'Follow up'
        }
        state['scheduled_check_in'] = {
          'job_id' => 'scheduled-job',
          'scheduled_for' => 1.day.from_now.iso8601,
          'intent' => 'Daily review'
        }
        goal.update_column(:runtime_state, state)
      end

      it 'only removes the specific check-in type that fired' do
        allow(Agents::Orchestrator).to receive(:perform_async)

        described_class.new.perform(
          'Goal',
          goal.id,
          'follow_up',
          check_in_data
        )

        goal.reload
        expect(goal.next_follow_up).to be_nil
        expect(goal.runtime_state['scheduled_check_in']).to be_present
      end
    end

    it 'handles non-existent agentable gracefully' do
      expect do
        described_class.new.perform(
          'Goal',
          99999,
          'follow_up',
          check_in_data
        )
      end.not_to raise_error
    end
  end
end
