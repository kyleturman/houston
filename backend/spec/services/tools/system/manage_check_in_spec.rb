# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::System::ManageCheckIn, type: :service do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }

  before do
    # Prevent infinite recursion in inline Sidekiq mode
    allow(AgentCheckInJob).to receive(:perform_at).and_return('test-job-id')
    allow(Streams::Broker).to receive(:publish)
  end

  describe '.metadata' do
    it 'returns correct tool metadata' do
      metadata = described_class.metadata

      expect(metadata[:name]).to eq('manage_check_in')
      expect(metadata[:description]).to include('Manage check-ins')
    end
  end

  describe '.schema' do
    it 'returns valid JSON schema' do
      schema = described_class.schema

      expect(schema[:type]).to eq('object')
      expect(schema[:properties]).to have_key(:action)
      expect(schema[:properties][:action][:enum]).to eq(%w[set_schedule schedule_follow_up clear_follow_up clear_schedule])
      expect(schema[:required]).to include('action')
    end
  end

  describe '#execute' do
    let(:tool) { described_class.new(agentable: goal, user: user) }

    context 'set_schedule' do
      it 'schedules a daily check-in' do
        result = tool.execute(
          action: 'set_schedule',
          frequency: 'daily',
          time: '9:00',
          intent: 'Review transactions'
        )

        expect(result[:success]).to be true
        expect(result[:observation]).to include('every day')

        schedule = goal.reload.check_in_schedule
        expect(schedule).to be_present
        expect(schedule['frequency']).to eq('daily')
        expect(schedule['time']).to eq('09:00')
        expect(schedule['intent']).to eq('Review transactions')
      end

      it 'schedules a weekly check-in' do
        result = tool.execute(
          action: 'set_schedule',
          frequency: 'weekly',
          time: '10am',
          day_of_week: 'monday',
          intent: 'Weekly review'
        )

        expect(result[:success]).to be true
        expect(result[:observation]).to include('every Monday')

        schedule = goal.reload.check_in_schedule
        expect(schedule['frequency']).to eq('weekly')
        expect(schedule['day_of_week']).to eq('monday')
      end

      it 'parses various time formats' do
        %w[9:00 09:00 9am 9:00am 14:30 2:30pm].each do |time|
          result = tool.execute(
            action: 'set_schedule',
            frequency: 'daily',
            time: time,
            intent: 'Test'
          )
          expect(result[:success]).to be(true), "Failed to parse time: #{time}"
        end
      end

      it 'rejects invalid time format' do
        result = tool.execute(
          action: 'set_schedule',
          frequency: 'daily',
          time: 'noon',
          intent: 'Test'
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Could not parse time')
      end

      it 'requires frequency parameter' do
        result = tool.execute(action: 'set_schedule', time: '9:00', intent: 'Test')

        expect(result[:success]).to be false
        expect(result[:error]).to include('frequency is required')
      end

      it 'requires time parameter' do
        result = tool.execute(action: 'set_schedule', frequency: 'daily', intent: 'Test')

        expect(result[:success]).to be false
        expect(result[:error]).to include('time is required')
      end

      it 'requires intent parameter' do
        result = tool.execute(action: 'set_schedule', frequency: 'daily', time: '9:00')

        expect(result[:success]).to be false
        expect(result[:error]).to include('intent is required')
      end

      it 'requires day_of_week for weekly schedule' do
        result = tool.execute(
          action: 'set_schedule',
          frequency: 'weekly',
          time: '9:00',
          intent: 'Test'
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('day_of_week is required')
      end
    end

    context 'schedule_follow_up' do
      it 'schedules a follow-up with valid delay' do
        result = tool.execute(
          action: 'schedule_follow_up',
          delay: '3 days',
          intent: 'Review recent notes'
        )

        expect(result[:success]).to be true
        expect(result[:observation]).to include('Review recent notes')

        follow_up = goal.reload.next_follow_up
        expect(follow_up).to be_present
        expect(follow_up['intent']).to eq('Review recent notes')
      end

      it 'parses hour delays' do
        result = tool.execute(
          action: 'schedule_follow_up',
          delay: '4 hours',
          intent: 'Quick check-in'
        )

        expect(result[:success]).to be true
      end

      it 'parses week delays' do
        result = tool.execute(
          action: 'schedule_follow_up',
          delay: '2 weeks',
          intent: 'Bi-weekly review'
        )

        expect(result[:success]).to be true
      end

      it 'parses absolute times' do
        result = tool.execute(
          action: 'schedule_follow_up',
          delay: 'tomorrow 9am',
          intent: 'Morning check-in'
        )

        expect(result[:success]).to be true
      end

      it 'rejects invalid delay format' do
        result = tool.execute(
          action: 'schedule_follow_up',
          delay: 'sometime',
          intent: 'Bad format'
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Could not parse delay')
      end

      it 'rejects delay above maximum' do
        result = tool.execute(
          action: 'schedule_follow_up',
          delay: '100 days',
          intent: 'Too far'
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('cannot be more than')
      end

      it 'replaces existing follow-up' do
        tool.execute(action: 'schedule_follow_up', delay: '3 days', intent: 'First follow-up')
        result = tool.execute(action: 'schedule_follow_up', delay: '5 days', intent: 'Second follow-up')

        expect(result[:success]).to be true
        follow_up = goal.reload.next_follow_up
        expect(follow_up['intent']).to eq('Second follow-up')
      end

      it 'requires delay parameter' do
        result = tool.execute(action: 'schedule_follow_up', intent: 'Missing delay')

        expect(result[:success]).to be false
        expect(result[:error]).to include('delay is required')
      end

      it 'requires intent parameter' do
        result = tool.execute(action: 'schedule_follow_up', delay: '3 days')

        expect(result[:success]).to be false
        expect(result[:error]).to include('intent is required')
      end
    end

    context 'clear_follow_up' do
      before do
        state = goal.runtime_state || {}
        state['next_follow_up'] = {
          'job_id' => 'test-job-123',
          'scheduled_for' => 3.days.from_now.iso8601,
          'intent' => 'Review notes'
        }
        goal.update_column(:runtime_state, state)
      end

      it 'clears a follow-up' do
        result = tool.execute(action: 'clear_follow_up')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('Cleared')

        follow_up = goal.reload.next_follow_up
        expect(follow_up).to be_nil
      end

      it 'returns error when no follow-up exists' do
        goal.update_column(:runtime_state, {})
        result = tool.execute(action: 'clear_follow_up')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No follow-up scheduled')
      end
    end

    context 'clear_schedule' do
      before do
        goal.update!(check_in_schedule: {
          'frequency' => 'daily',
          'time' => '09:00',
          'intent' => 'Daily review'
        })
      end

      it 'clears a schedule' do
        result = tool.execute(action: 'clear_schedule')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('Cleared')

        schedule = goal.reload.check_in_schedule
        expect(schedule).to be_nil
      end

      it 'returns error when no schedule exists' do
        goal.update!(check_in_schedule: nil)
        result = tool.execute(action: 'clear_schedule')

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No recurring schedule set')
      end
    end

    context 'with invalid parameters' do
      it 'returns error for invalid action' do
        result = tool.execute(action: 'invalid')

        expect(result[:success]).to be false
        expect(result[:error]).to include('set_schedule')
      end
    end

    context 'with non-goal agentable' do
      let(:task) { create(:agent_task, user: user, goal: goal) }
      let(:tool) { described_class.new(agentable: task, user: user) }

      it 'rejects check-in for tasks' do
        result = tool.execute(
          action: 'set_schedule',
          frequency: 'daily',
          time: '9:00',
          intent: 'Task check-in'
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Only goal agents')
      end
    end
  end
end
