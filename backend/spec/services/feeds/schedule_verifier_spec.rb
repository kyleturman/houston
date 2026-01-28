# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/api'

RSpec.describe Feeds::ScheduleVerifier do
  let(:user) { create(:user) }
  let(:user_agent) { user.user_agent }
  let(:scheduled_set) { instance_double(Sidekiq::ScheduledSet) }
  let(:verifier) { described_class.new(user_agent) }

  describe '#verify_and_repair!' do
    context 'when feed schedule is disabled' do
      before do
        user_agent.update_runtime_state! do |state|
          state['feed_schedule'] = { 'enabled' => false }
        end
      end

      it 'returns :skipped' do
        result = verifier.verify_and_repair!(scheduled_set: scheduled_set)
        expect(result).to eq(:skipped)
      end
    end

    context 'when no feed schedule exists' do
      before do
        # Clear the schedule auto-created by user_agent setup
        user_agent.update_runtime_state! do |state|
          state.delete('feed_schedule')
        end
      end

      it 'returns :skipped' do
        result = verifier.verify_and_repair!(scheduled_set: scheduled_set)
        expect(result).to eq(:skipped)
      end
    end

    context 'when feed schedule has no jobs' do
      before do
        user_agent.update_runtime_state! do |state|
          state['feed_schedule'] = { 'enabled' => true, 'jobs' => {} }
        end
      end

      it 'returns :skipped' do
        result = verifier.verify_and_repair!(scheduled_set: scheduled_set)
        expect(result).to eq(:skipped)
      end
    end

    context 'when all jobs exist in Sidekiq' do
      let(:job_id) { 'valid_job_123' }

      before do
        user_agent.update_runtime_state! do |state|
          state['feed_schedule'] = {
            'enabled' => true,
            'jobs' => {
              'morning' => { 'job_id' => job_id, 'scheduled_for' => 1.day.from_now.iso8601 }
            }
          }
        end

        mock_job = double('SidekiqJob', jid: job_id)
        allow(scheduled_set).to receive(:find_job).with(job_id).and_return(mock_job)
      end

      it 'returns :healthy' do
        result = verifier.verify_and_repair!(scheduled_set: scheduled_set)
        expect(result).to eq(:healthy)
      end
    end

    context 'when jobs are missing from Sidekiq' do
      before do
        user_agent.update_runtime_state! do |state|
          state['feed_schedule'] = {
            'enabled' => true,
            'periods' => {
              'morning' => { 'enabled' => true, 'time' => '06:00' }
            },
            'jobs' => {
              'morning' => { 'job_id' => 'missing_job_456', 'scheduled_for' => 1.day.from_now.iso8601 }
            }
          }
        end

        # Sidekiq scheduled set returns nothing (job is missing)
        allow(scheduled_set).to receive(:find_job).and_return(nil)
      end

      it 'repairs the schedule and returns :repaired' do
        scheduler = instance_double(Feeds::InsightScheduler)
        allow(Feeds::InsightScheduler).to receive(:new).with(user_agent).and_return(scheduler)
        allow(scheduler).to receive(:cancel_all!)
        allow(scheduler).to receive(:schedule_all!)

        result = verifier.verify_and_repair!(scheduled_set: scheduled_set)

        expect(result).to eq(:repaired)
        expect(scheduler).to have_received(:cancel_all!)
        expect(scheduler).to have_received(:schedule_all!)
      end
    end
  end
end
