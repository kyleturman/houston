# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Agent History Lifecycle', type: :integration do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }

  # Helper to create enough thread messages to satisfy archiving threshold
  # Archiving requires either 12+ thread messages OR 24+ hour session age
  def create_thread_messages_for_archive(goal, count: 12)
    count.times do |i|
      ThreadMessage.create!(
        agentable: goal,
        user: goal.user,
        source: :user,
        content: "Message #{i}"
      )
    end
  end

  describe 'session timeout archiving' do
    it 'archives stale session when starting new orchestrator run' do
      # Simulate an old session
      goal.add_to_llm_history({ role: 'user', content: 'Old question' })
      goal.start_agent_turn_if_needed!
      create_thread_messages_for_archive(goal) # Need enough messages to trigger archive

      # Make the session appear stale (>30 minutes old)
      old_time = (Agents::Constants::SESSION_TIMEOUT + 1.minute).ago
      goal.update_column(:runtime_state, goal.runtime_state.merge(
        'current_turn_started_at' => old_time.iso8601
      ))

      expect(goal.llm_history.length).to eq(1)
      expect(goal.agent_histories.count).to eq(0)

      # Start new orchestrator run (would happen in perform method)
      orchestrator = Agents::Orchestrator.new
      orchestrator.instance_variable_set(:@agentable, goal)
      orchestrator.send(:archive_stale_session_if_needed!)

      # Should have archived
      expect(goal.reload.llm_history).to be_empty
      expect(goal.agent_histories.count).to eq(1)
      expect(goal.agent_histories.last.completion_reason).to eq('session_timeout')
    end

    it 'does not archive if session is recent' do
      goal.add_to_llm_history({ role: 'user', content: 'Recent question' })
      goal.start_agent_turn_if_needed!

      # Session is only 5 minutes old
      recent_time = 5.minutes.ago
      goal.update_column(:runtime_state, goal.runtime_state.merge(
        'current_turn_started_at' => recent_time.iso8601
      ))

      orchestrator = Agents::Orchestrator.new
      orchestrator.instance_variable_set(:@agentable, goal)
      orchestrator.send(:archive_stale_session_if_needed!)

      # Should NOT have archived
      expect(goal.reload.llm_history.length).to eq(1)
      expect(goal.agent_histories.count).to eq(0)
    end
  end

  describe 'feed generation archiving' do
    it 'archives immediately after feed generation completes' do
      goal.add_to_llm_history({ role: 'user', content: 'Feed generation' })
      goal.add_to_llm_history({ role: 'assistant', content: [{ 'type' => 'tool_use', 'id' => 'tool_1', 'name' => 'create_task', 'input' => {} }] })
      goal.start_agent_turn_if_needed!
      create_thread_messages_for_archive(goal) # Need enough messages to trigger archive

      orchestrator = Agents::Orchestrator.new
      orchestrator.instance_variable_set(:@agentable, goal)
      orchestrator.instance_variable_set(:@context, { 'type' => 'feed_generation' })
      orchestrator.instance_variable_set(:@user, user)
      orchestrator.instance_variable_set(:@start_time, Time.current)

      expect {
        orchestrator.send(:handle_feed_generation_completion)
      }.to change(goal.agent_histories, :count).by(1)

      expect(goal.agent_histories.last.completion_reason).to eq('feed_generation_complete')
      expect(goal.reload.llm_history).to be_empty
    end

    it 'does not archive if not feed generation' do
      goal.add_to_llm_history({ role: 'user', content: 'Normal message' })
      goal.start_agent_turn_if_needed!

      orchestrator = Agents::Orchestrator.new
      orchestrator.instance_variable_set(:@agentable, goal)
      orchestrator.instance_variable_set(:@context, {})

      expect {
        orchestrator.send(:handle_feed_generation_completion)
      }.not_to change(goal.agent_histories, :count)
    end
  end

  describe 'concurrent archiving safety' do
    it 'prevents double archiving with lock' do
      skip 'Threading in test environment can be flaky with transactional fixtures'

      goal.add_to_llm_history({ role: 'user', content: 'Test' })
      goal.start_agent_turn_if_needed!

      # Simulate two concurrent requests
      threads = 2.times.map do
        Thread.new do
          goal.reload
          goal.archive_agent_turn!(reason: 'test') rescue nil
        end
      end

      threads.each(&:join)

      # Should only create one archive
      expect(goal.agent_histories.count).to eq(1)
    end
  end

  describe 'context building with agent history' do
    before do
      # Create some archived sessions
      3.times do |i|
        goal.agent_histories.create!(
          agent_history: [{ role: 'user', content: "Question #{i}" }],
          summary: "User asked about topic #{i}",
          message_count: 1,
          token_count: 100,
          completed_at: i.days.ago
        )
      end
    end

    it 'includes agent history in system prompt' do
      orchestrator = Agents::Orchestrator.new
      orchestrator.instance_variable_set(:@agentable, goal)
      orchestrator.instance_variable_set(:@user, user)

      prompt = orchestrator.send(:build_system_prompt)

      expect(prompt).to include('<your_memory>')
      expect(prompt).to include('User asked about topic 0')
      expect(prompt).to include('User asked about topic 1')
      expect(prompt).to include('User asked about topic 2')
    end

    it 'does not include agent history if none exists' do
      goal.agent_histories.destroy_all

      orchestrator = Agents::Orchestrator.new
      orchestrator.instance_variable_set(:@agentable, goal)
      orchestrator.instance_variable_set(:@user, user)

      prompt = orchestrator.send(:build_system_prompt)

      expect(prompt).not_to include('<your_memory>')
    end
  end

  describe 'search tool availability' do
    let(:registry) { Tools::Registry.new(user: user, goal: goal, task: nil, agentable: goal) }

    it 'includes search_agent_history when history exists' do
      goal.agent_histories.create!(
        agent_history: [{ role: 'user', content: 'test' }],
        summary: 'Test session',
        message_count: 1,
        token_count: 100,
        completed_at: Time.current
      )

      tools = registry.send(:enabled_tools_for_context, :goal)
      expect(tools).to include('search_agent_history')
    end

    it 'excludes search_agent_history when no history' do
      goal.agent_histories.destroy_all
      goal.reload

      tools = registry.send(:enabled_tools_for_context, :goal)
      expect(tools).not_to include('search_agent_history')
    end

    it 'excludes search_agent_history for tasks' do
      task = create(:agent_task, user: user, goal: goal)
      task_registry = Tools::Registry.new(user: user, goal: goal, task: task, agentable: task)

      tools = task_registry.send(:enabled_tools_for_context, :task)
      expect(tools).not_to include('search_agent_history')
    end
  end

  describe 'multi-session flow' do
    it 'accumulates history over multiple sessions' do
      # Session 1
      goal.add_to_llm_history({ role: 'user', content: 'First question' })
      goal.start_agent_turn_if_needed!
      create_thread_messages_for_archive(goal) # Need enough messages to trigger archive
      goal.archive_agent_turn!(reason: 'session_timeout')

      # Session 2
      goal.add_to_llm_history({ role: 'user', content: 'Second question' })
      goal.start_agent_turn_if_needed!
      create_thread_messages_for_archive(goal)
      goal.archive_agent_turn!(reason: 'session_timeout')

      # Session 3 (autonomous feed generation - requires tool calls to archive)
      goal.add_to_llm_history({ role: 'user', content: 'Third question' })
      goal.add_to_llm_history({ role: 'assistant', content: [{ 'type' => 'tool_use', 'id' => 'tool_1', 'name' => 'generate_feed_insights', 'input' => {} }] })
      goal.start_agent_turn_if_needed!
      create_thread_messages_for_archive(goal)
      goal.archive_agent_turn!(reason: 'feed_generation_complete')

      expect(goal.agent_histories.count).to eq(3)
      expect(goal.agent_histories.pluck(:completion_reason)).to match_array([
        'session_timeout',
        'session_timeout',
        'feed_generation_complete'
      ])
    end

    it 'retrieves correct number of summaries for context' do
      # Create 10 sessions
      10.times do |i|
        goal.agent_histories.create!(
          agent_history: [{ role: 'user', content: "Question #{i}" }],
          summary: "Summary #{i}",
          message_count: 1,
          token_count: 100,
          completed_at: i.days.ago
        )
      end

      summaries = goal.recent_agent_history_summaries(
        limit: Agents::Constants::AGENT_HISTORY_SUMMARY_COUNT
      )

      expect(summaries.length).to eq(5)
      expect(summaries.first).to include('Summary 0')  # Most recent
    end
  end
end
