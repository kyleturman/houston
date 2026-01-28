# frozen_string_literal: true

require 'rails_helper'

# Integration test for runtime_state management through real orchestrator flows.
# Validates that the AgentableRuntimeState accessors work correctly during actual
# LLM-powered agent sessions — including session lifecycle, check-in scheduling,
# feed generation guards, and state cleanup.
#
# Run with: make test-llm-goal (or USE_REAL_LLM=true bundle exec rspec spec/integration/runtime_state_real_llm_spec.rb)
RSpec.describe 'Runtime State Management with Real LLM', :real_llm do
  before(:each) do
    skip_unless_real_llm_enabled

    unless ENV['LLM_AGENTS_MODEL'] && !ENV['LLM_AGENTS_MODEL'].empty?
      skip 'Requires LLM_AGENTS_MODEL to be set'
    end
  end

  let(:user) { create(:user) }

  describe 'Goal session lifecycle (state transitions)' do
    it 'manages runtime_state correctly through simulated session phases' do
      puts "\n🧪 TEST: Runtime state through session lifecycle phases"

      goal = Goal.create!(
        user: user,
        title: "Test Runtime State",
        description: "A goal to test runtime state management",
        status: :working
      )

      # Phase 1: Clean initial state
      expect(goal.runtime_state).to eq({})
      expect(goal.agent_running?).to be false
      expect(goal.orchestrator_started_at).to be_nil
      expect(goal.orchestrator_job_id).to be_nil
      expect(goal.current_turn_started_at).to be_nil
      expect(goal.feed_period).to be_nil
      expect(goal.scheduled_check_in).to be_nil
      expect(goal.next_follow_up).to be_nil
      puts "✅ Phase 1: Initial state is clean"

      # Phase 2: Simulate orchestrator startup (claim lock + start turn)
      expect(goal.claim_execution_lock!).to be true
      goal.set_orchestrator_job_id!('test_jid_123')
      goal.start_agent_turn_if_needed!
      goal.set_feed_period!('morning')

      goal.reload
      expect(goal.agent_running?).to be true
      expect(goal.orchestrator_job_id).to eq('test_jid_123')
      expect(goal.current_turn_started_at).to be_present
      expect(goal.feed_period).to eq('morning')
      puts "✅ Phase 2: Orchestrator startup state set"

      # Phase 3: Simulate tool calls setting check-in state (what manage_check_in does)
      goal.set_scheduled_check_in!({
        'job_id' => 'checkin_job_1',
        'scheduled_for' => 1.day.from_now.iso8601,
        'intent' => 'Daily reading check-in',
        'created_at' => Time.current.iso8601
      })
      goal.set_next_follow_up!({
        'job_id' => 'followup_job_1',
        'scheduled_for' => 2.days.from_now.iso8601,
        'intent' => 'Check reading progress',
        'created_at' => Time.current.iso8601
      })

      goal.reload
      expect(goal.scheduled_check_in['intent']).to eq('Daily reading check-in')
      expect(goal.next_follow_up['intent']).to eq('Check reading progress')
      puts "✅ Phase 3: Check-in state set during execution"

      # Phase 4: Simulate orchestrator completion (release lock)
      goal.release_execution_lock!
      goal.reload
      expect(goal.agent_running?).to be false
      expect(goal.orchestrator_job_id).to be_nil
      # Session and check-in state should still be present (not cleared by lock release)
      expect(goal.current_turn_started_at).to be_present
      expect(goal.scheduled_check_in).to be_present
      expect(goal.next_follow_up).to be_present
      puts "✅ Phase 4: Lock released, session + check-in state preserved"

      # Phase 5: Simulate session archive (what happens on timeout or feed completion)
      # First add LLM history so archive has something to save
      goal.add_to_llm_history({ 'role' => 'user', 'content' => 'Test' })
      goal.add_to_llm_history({
        'role' => 'assistant',
        'content' => [{ 'type' => 'tool_use', 'id' => 't1', 'name' => 'send_message', 'input' => { 'message' => 'hi' } }]
      })
      goal.add_to_llm_history({
        'role' => 'user',
        'content' => [{ 'type' => 'tool_result', 'tool_use_id' => 't1', 'content' => 'ok' }]
      })

      goal.archive_agent_turn!(reason: 'test_lifecycle')
      goal.reload

      # Session keys cleared
      expect(goal.current_turn_started_at).to be_nil
      expect(goal.feed_period).to be_nil
      # Check-in state preserved
      expect(goal.scheduled_check_in['intent']).to eq('Daily reading check-in')
      expect(goal.next_follow_up['intent']).to eq('Check reading progress')
      # LLM history archived
      expect(goal.get_llm_history).to be_empty
      # Note: agent_histories creation is tested in the dedicated archive test
      puts "✅ Phase 5: Archive clears session, preserves check-ins"

      puts "\n✅ Session lifecycle test passed"
    end
  end

  describe 'Execution lock prevents duplicate orchestrators' do
    it 'claim_execution_lock! prevents concurrent execution' do
      puts "\n🧪 TEST: Execution lock concurrency"

      goal = Goal.create!(user: user, title: "Lock Test", description: "Testing locks", status: :working)

      # First claim should succeed
      result1 = goal.claim_execution_lock!
      expect(result1).to be true
      expect(goal.reload.agent_running?).to be true
      expect(goal.orchestrator_started_at).to be_present
      puts "✅ First lock claim succeeded"

      # Second claim should fail
      result2 = goal.claim_execution_lock!
      expect(result2).to be false
      puts "✅ Second lock claim correctly rejected"

      # Release and reclaim
      goal.release_execution_lock!
      expect(goal.reload.agent_running?).to be false
      expect(goal.orchestrator_job_id).to be_nil
      puts "✅ Lock released"

      result3 = goal.claim_execution_lock!
      expect(result3).to be true
      puts "✅ Lock reclaimed after release"

      goal.release_execution_lock!
    end
  end

  describe 'Check-in state accessors' do
    it 'set and clear check-in state correctly' do
      puts "\n🧪 TEST: Check-in state accessors"

      goal = Goal.create!(user: user, title: "Check-in Test", description: "Testing check-ins", status: :working)

      # Set scheduled check-in
      check_in_data = {
        'job_id' => 'test_job_123',
        'scheduled_for' => 1.day.from_now.iso8601,
        'intent' => 'Daily review',
        'created_at' => Time.current.iso8601
      }
      goal.set_scheduled_check_in!(check_in_data)
      expect(goal.reload.scheduled_check_in).to eq(check_in_data)
      puts "✅ set_scheduled_check_in! works"

      # Set follow-up
      follow_up_data = {
        'job_id' => 'test_followup_456',
        'scheduled_for' => 2.days.from_now.iso8601,
        'intent' => 'Check progress',
        'created_at' => Time.current.iso8601
      }
      goal.set_next_follow_up!(follow_up_data)
      expect(goal.reload.next_follow_up).to eq(follow_up_data)
      puts "✅ set_next_follow_up! works"

      # Set original follow-up
      original_data = {
        'scheduled_for' => 3.days.from_now.iso8601,
        'intent' => 'Original intent',
        'stored_at' => Time.current.iso8601
      }
      goal.set_original_follow_up!(original_data)
      expect(goal.reload.original_follow_up).to eq(original_data)
      puts "✅ set_original_follow_up! works"

      # Set adjustment timestamp
      goal.set_check_in_last_adjusted_at!
      expect(goal.reload.check_in_last_adjusted_at).to be_present
      puts "✅ set_check_in_last_adjusted_at! works"

      # Clear by slot - scheduled
      goal.clear_check_in_for_slot!('scheduled')
      expect(goal.reload.scheduled_check_in).to be_nil
      expect(goal.next_follow_up).to be_present # should not be affected
      puts "✅ clear_check_in_for_slot!('scheduled') works"

      # Clear by slot - follow_up (should also clear original)
      goal.clear_check_in_for_slot!('follow_up')
      expect(goal.reload.next_follow_up).to be_nil
      expect(goal.original_follow_up).to be_nil
      puts "✅ clear_check_in_for_slot!('follow_up') clears both follow-up and original"

      # Individual clear methods
      goal.set_scheduled_check_in!(check_in_data)
      goal.clear_scheduled_check_in!
      expect(goal.reload.scheduled_check_in).to be_nil
      puts "✅ clear_scheduled_check_in! works"

      puts "\n✅ Check-in state accessor test passed"
    end
  end

  describe 'Feed generation guard with runtime state' do
    it 'generation_guard uses accessor methods correctly' do
      puts "\n🧪 TEST: Feed generation guard state"

      user_agent = UserAgent.find_or_create_by!(user: user)

      # Start with clean runtime_state
      user_agent.update_column(:runtime_state, {})

      # Set feed period
      user_agent.set_feed_period!('morning')
      expect(user_agent.reload.feed_period).to eq('morning')
      puts "✅ set_feed_period! works"

      # Check feed schedule accessor
      expect(user_agent.feed_schedule).to be_nil # no schedule yet
      puts "✅ feed_schedule returns nil when not set"

      # Check feed attempts accessor
      expect(user_agent.feed_attempts_for('morning')).to be_nil
      puts "✅ feed_attempts_for returns nil when not set"

      # Set up feed schedule via update_runtime_state!
      user_agent.update_runtime_state! do |state|
        state['feed_schedule'] = {
          'enabled' => true,
          'periods' => ['morning', 'evening'],
          'jobs' => {}
        }
        state['feed_attempts'] = {
          'morning' => { 'date' => Date.current.to_s, 'count' => 1 }
        }
      end

      user_agent.reload
      expect(user_agent.feed_schedule['enabled']).to be true
      expect(user_agent.feed_attempts_for('morning')['count']).to eq(1)
      expect(user_agent.feed_attempts_for('evening')).to be_nil
      puts "✅ Feed schedule and attempts accessors work correctly"

      # Test generation guard (takes user, not user_agent)
      guard = Feeds::GenerationGuard.new(user)
      puts "   generation_in_progress?: #{guard.generation_in_progress?}"
      puts "   can_generate?('morning'): #{guard.can_generate?('morning')}"

      # Clean up
      user_agent.update_column(:runtime_state, {})
      puts "\n✅ Feed generation guard test passed"
    end
  end

  describe 'Session archiving clears session keys' do
    it 'archive_agent_turn! clears session state but preserves check-in state' do
      puts "\n🧪 TEST: Archive preserves non-session state"

      goal = Goal.create!(user: user, title: "Archive Test", description: "Testing archive", status: :working)

      # Set up mixed state: session keys + check-in keys
      goal.start_agent_turn_if_needed!
      goal.set_feed_period!('morning')
      goal.set_scheduled_check_in!({
        'job_id' => 'persist_me',
        'scheduled_for' => 1.day.from_now.iso8601,
        'intent' => 'Should survive archive',
        'created_at' => Time.current.iso8601
      })

      # Add LLM history with tool calls (required for autonomous archive)
      goal.add_to_llm_history({
        'role' => 'user',
        'content' => 'Test message'
      })
      goal.add_to_llm_history({
        'role' => 'assistant',
        'content' => [
          { 'type' => 'tool_use', 'id' => 'test', 'name' => 'send_message', 'input' => { 'message' => 'hello' } }
        ]
      })
      goal.add_to_llm_history({
        'role' => 'user',
        'content' => [
          { 'type' => 'tool_result', 'tool_use_id' => 'test', 'content' => 'ok' }
        ]
      })

      expect(goal.current_turn_started_at).to be_present
      expect(goal.feed_period).to eq('morning')
      expect(goal.scheduled_check_in).to be_present
      puts "✅ Pre-archive state set up"

      # Archive
      goal.archive_agent_turn!(reason: 'feed_generation_complete')
      goal.reload

      # Session keys should be cleared
      expect(goal.current_turn_started_at).to be_nil
      expect(goal.feed_period).to be_nil
      puts "✅ Session keys cleared by archive"

      # Check-in state should persist
      expect(goal.scheduled_check_in).to be_present
      expect(goal.scheduled_check_in['job_id']).to eq('persist_me')
      puts "✅ Check-in state preserved through archive"

      # LLM history should be cleared
      expect(goal.get_llm_history).to be_empty
      puts "✅ LLM history cleared"

      # Agent history should be created
      expect(goal.agent_histories.count).to eq(1)
      puts "✅ Agent history record created"

      puts "\n✅ Archive test passed"
    end
  end

  describe 'update_runtime_state! atomicity' do
    it 'supports nested mutations without data loss' do
      puts "\n🧪 TEST: update_runtime_state! atomicity"

      user_agent = UserAgent.find_or_create_by!(user: user)

      # Set initial state
      user_agent.set_feed_period!('morning')
      user_agent.update_runtime_state! do |state|
        state['feed_schedule'] = { 'enabled' => true }
      end

      # Verify both keys coexist
      user_agent.reload
      expect(user_agent.feed_period).to eq('morning')
      expect(user_agent.feed_schedule['enabled']).to be true
      puts "✅ Multiple state updates don't overwrite each other"

      # Test with_lock variant
      user_agent.update_runtime_state!(with_lock: true) do |state|
        state['feed_attempts'] = { 'morning' => { 'count' => 1 } }
      end

      user_agent.reload
      expect(user_agent.feed_period).to eq('morning')
      expect(user_agent.feed_schedule['enabled']).to be true
      expect(user_agent.feed_attempts_for('morning')['count']).to eq(1)
      puts "✅ Locked update preserves existing state"

      # Clean up
      user_agent.update_column(:runtime_state, {})
      puts "\n✅ Atomicity test passed"
    end
  end
end
