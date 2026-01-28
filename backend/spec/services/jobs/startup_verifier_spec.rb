# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/api'

RSpec.describe Jobs::StartupVerifier do
  let(:user) { create(:user) }

  # Default mock: no active Sidekiq jobs
  before do
    allow(Sidekiq::Workers).to receive(:new).and_return([])
    allow(Sidekiq::Queue).to receive(:new).and_return([])
  end

  describe '#verify!' do
    describe 'execution lock cleanup' do
      context 'with orphaned execution lock (job no longer exists)' do
        let!(:goal) { create(:goal, user: user) }

        before do
          # Simulate a lock that was set but the job no longer exists
          goal.update_column(:runtime_state, {
            'orchestrator_running' => true,
            'orchestrator_started_at' => 5.minutes.ago.iso8601,
            'orchestrator_job_id' => 'nonexistent_job_id_123'
          })
        end

        it 'clears the orphaned lock' do
          result = described_class.verify!

          goal.reload
          expect(goal.runtime_state['orchestrator_running']).to be false
          expect(result[:locks_cleared]).to eq(1)
        end

        it 'repairs corrupted LLM history while clearing lock' do
          # Add corrupted history with orphaned tool_use
          goal.update_column(:llm_history, [
            {
              'role' => 'assistant',
              'content' => [
                { 'type' => 'tool_use', 'id' => 'toolu_orphaned', 'name' => 'search_notes', 'input' => {} }
              ]
            }
          ])

          described_class.verify!

          goal.reload
          expect(goal.llm_history.length).to eq(2)
          tool_result = goal.llm_history.last['content'].first
          expect(tool_result['type']).to eq('tool_result')
          expect(tool_result['is_error']).to be true
        end
      end

      context 'with stale execution lock (very old)' do
        let!(:task) { create(:agent_task, user: user) }

        before do
          # Simulate a lock that's been held for too long (>30 min)
          task.update_column(:runtime_state, {
            'orchestrator_running' => true,
            'orchestrator_started_at' => 45.minutes.ago.iso8601,
            'orchestrator_job_id' => 'some_job_id'
          })
        end

        it 'clears stale locks even if job might exist' do
          result = described_class.verify!

          task.reload
          expect(task.runtime_state['orchestrator_running']).to be false
          expect(result[:locks_cleared]).to eq(1)
        end
      end

      context 'with lock but no job_id stored' do
        let!(:user_agent) { user.user_agent }

        before do
          # Simulate a lock without job_id (shouldn't happen, but defensive)
          user_agent.update_column(:runtime_state, {
            'orchestrator_running' => true,
            'orchestrator_started_at' => 2.minutes.ago.iso8601
            # No orchestrator_job_id
          })
        end

        it 'clears the lock' do
          result = described_class.verify!

          user_agent.reload
          expect(user_agent.runtime_state['orchestrator_running']).to be false
          expect(result[:locks_cleared]).to eq(1)
        end
      end

      context 'with healthy execution (lock is recent and has valid job)' do
        let!(:goal) { create(:goal, user: user) }
        let(:job_id) { 'active_job_123' }

        before do
          goal.update_column(:runtime_state, {
            'orchestrator_running' => true,
            'orchestrator_started_at' => 1.minute.ago.iso8601,
            'orchestrator_job_id' => job_id
          })

          # Mock Sidekiq to show this job as active
          mock_workers = [['process', 'thread', { 'payload' => { 'jid' => job_id } }]]
          allow(Sidekiq::Workers).to receive(:new).and_return(mock_workers)
          allow(Sidekiq::Queue).to receive(:new).and_return([])
        end

        it 'does not clear the lock' do
          result = described_class.verify!

          goal.reload
          expect(goal.runtime_state['orchestrator_running']).to be true
          expect(result[:locks_cleared]).to eq(0)
        end
      end

      context 'with no locks' do
        let!(:goal) { create(:goal, user: user) }

        it 'reports zero locks cleared' do
          result = described_class.verify!
          expect(result[:locks_cleared]).to eq(0)
        end
      end
    end
  end

  describe '.heartbeat_healthy?' do
    context 'with recent heartbeat' do
      before do
        described_class.write_heartbeat!
      end

      it 'returns true' do
        expect(described_class.heartbeat_healthy?).to be true
      end
    end

    context 'with no heartbeat' do
      before do
        Sidekiq.redis { |r| r.del(described_class::HEARTBEAT_KEY) }
      end

      it 'returns false' do
        expect(described_class.heartbeat_healthy?).to be false
      end
    end
  end
end
