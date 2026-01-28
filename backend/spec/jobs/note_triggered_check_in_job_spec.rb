# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NoteTriggeredCheckInJob do
  include_context 'authenticated user with goal'
  include ActiveSupport::Testing::TimeHelpers

  describe '#perform' do
    context 'with no existing follow-up' do
      it 'creates a follow-up' do
        expect {
          described_class.new.perform(goal.id)
        }.to change { goal.reload.next_follow_up }.from(nil)
      end

      it 'schedules follow-up within max delay' do
        described_class.new.perform(goal.id)
        goal.reload

        scheduled_for = Time.parse(goal.next_follow_up['scheduled_for'])
        max_delay = Agents::Constants::NOTE_TRIGGERED_DELAY_MINUTES.minutes

        expect(scheduled_for).to be <= max_delay.from_now
      end

      it 'sets intent to review notes' do
        described_class.new.perform(goal.id)
        goal.reload

        intent = goal.next_follow_up['intent']
        expect(intent).to eq('Review recent notes')
      end
    end

    context 'with existing follow-up far in the future' do
      before do
        # Schedule a follow-up 12 hours from now
        state = goal.runtime_state || {}
        state['next_follow_up'] = {
          'job_id' => 'old_job_123',
          'scheduled_for' => 12.hours.from_now.iso8601,
          'intent' => 'Old check-in',
          'created_at' => Time.current.iso8601
        }
        goal.update_column(:runtime_state, state)
      end

      it 'pulls follow-up closer to within max delay' do
        old_time = Time.parse(goal.next_follow_up['scheduled_for'])

        described_class.new.perform(goal.id)
        goal.reload

        new_time = Time.parse(goal.next_follow_up['scheduled_for'])
        max_delay = Agents::Constants::NOTE_TRIGGERED_DELAY_MINUTES.minutes

        expect(new_time).to be < old_time
        expect(new_time).to be <= max_delay.from_now
      end

      it 'stores original follow-up info' do
        described_class.new.perform(goal.id)
        goal.reload

        original = goal.runtime_state['original_follow_up']
        expect(original).to be_present
        expect(original['scheduled_for']).to eq(12.hours.from_now.iso8601)
        expect(original['intent']).to eq('Old check-in')
      end

      it 'updates intent to review notes' do
        described_class.new.perform(goal.id)
        goal.reload

        intent = goal.next_follow_up['intent']
        expect(intent).to eq('Review recent notes')
      end
    end

    context 'with existing follow-up already soon' do
      before do
        # Schedule a follow-up 10 minutes from now (already within 15 minute window)
        state = goal.runtime_state || {}
        state['next_follow_up'] = {
          'job_id' => 'existing_job_456',
          'scheduled_for' => 10.minutes.from_now.iso8601,
          'intent' => 'Already scheduled',
          'created_at' => Time.current.iso8601
        }
        goal.update_column(:runtime_state, state)
      end

      it 'does not reschedule' do
        original_job_id = goal.next_follow_up['job_id']

        described_class.new.perform(goal.id)
        goal.reload

        new_job_id = goal.next_follow_up['job_id']
        expect(new_job_id).to eq(original_job_id)
      end

      it 'preserves original intent' do
        described_class.new.perform(goal.id)
        goal.reload

        intent = goal.next_follow_up['intent']
        expect(intent).to eq('Already scheduled')
      end
    end

    context 'with debouncing' do
      before do
        # Mark as recently adjusted
        state = goal.runtime_state || {}
        state['check_in_last_adjusted_at'] = 5.minutes.ago.iso8601
        goal.update_column(:runtime_state, state)
      end

      it 'skips when recently adjusted' do
        expect {
          described_class.new.perform(goal.id)
        }.not_to change { goal.reload.next_follow_up }
      end
    end

    context 'with debounce window expired' do
      before do
        # Mark as adjusted outside debounce window
        debounce_minutes = Agents::Constants::NOTE_TRIGGERED_DEBOUNCE_MINUTES
        state = goal.runtime_state || {}
        state['check_in_last_adjusted_at'] = (debounce_minutes + 5).minutes.ago.iso8601
        goal.update_column(:runtime_state, state)
      end

      it 'creates follow-up after debounce window expires' do
        expect {
          described_class.new.perform(goal.id)
        }.to change { goal.reload.next_follow_up }.from(nil)
      end
    end

    context 'with inactive goal' do
      before do
        goal.update!(status: :archived)
      end

      it 'does not create follow-up' do
        expect {
          described_class.new.perform(goal.id)
        }.not_to change { goal.reload.next_follow_up }
      end
    end

    context 'with non-existent goal' do
      it 'handles gracefully' do
        expect {
          described_class.new.perform(0)
        }.not_to raise_error
      end
    end

    context 'with scheduled check-in coming soon' do
      before do
        goal.update!(check_in_schedule: {
          'frequency' => 'daily',
          'time' => '09:00',
          'intent' => 'Daily review'
        })

        # Mock the schedule calculator to say check-in is in 30 minutes
        allow_any_instance_of(Goals::ScheduleCalculator).to receive(:hours_until_next).and_return(0.5)
      end

      it 'does not create follow-up when scheduled check-in is soon' do
        expect {
          described_class.new.perform(goal.id)
        }.not_to change { goal.reload.next_follow_up }
      end
    end
  end
end
