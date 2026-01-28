# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Agentable Agent History', type: :model do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }

  # Helper to create enough thread messages to satisfy archiving threshold
  # Archiving requires either 12+ thread messages OR 24+ hour session age
  def create_thread_messages_for_archive(agentable, count: 12)
    count.times do |i|
      ThreadMessage.create!(
        agentable: agentable,
        user: agentable.respond_to?(:user) ? agentable.user : user,
        source: :user,
        content: "Message #{i}"
      )
    end
  end

  describe '#start_agent_turn_if_needed!' do
    it 'sets current_turn_started_at on first call' do
      expect(goal.runtime_state).not_to have_key('current_turn_started_at')

      goal.start_agent_turn_if_needed!

      expect(goal.reload.runtime_state['current_turn_started_at']).to be_present
    end

    it 'is idempotent - does not reset timestamp' do
      goal.start_agent_turn_if_needed!
      first_timestamp = goal.runtime_state['current_turn_started_at']

      sleep 0.1
      goal.start_agent_turn_if_needed!

      expect(goal.reload.runtime_state['current_turn_started_at']).to eq(first_timestamp)
    end
  end

  describe '#archive_agent_turn!' do
    before do
      # Add some llm_history
      3.times do |i|
        goal.add_to_llm_history({
          role: 'user',
          content: "Test message #{i}"
        })
      end
      goal.start_agent_turn_if_needed!
      # Create enough thread messages to satisfy archiving threshold
      create_thread_messages_for_archive(goal)
    end

    it 'creates an agent_history record' do
      expect {
        goal.archive_agent_turn!(reason: 'session_timeout')
      }.to change(AgentHistory, :count).by(1)
    end

    it 'saves the full llm_history' do
      goal.archive_agent_turn!(reason: 'session_timeout')

      history = goal.agent_histories.last
      expect(history.agent_history.length).to eq(3)
      expect(history.agent_history.first['content']).to eq('Test message 0')
    end

    it 'generates a summary' do
      goal.archive_agent_turn!(reason: 'session_timeout')

      history = goal.agent_histories.last
      expect(history.summary).to be_present
      expect(history.summary.length).to be > 10
    end

    it 'uses fallback summary if LLM fails', :skip_vcr do
      # Mock LLM failure
      allow(Llms::Service).to receive(:call).and_raise(StandardError, 'API error')

      goal.archive_agent_turn!(reason: 'session_timeout')

      history = goal.agent_histories.last
      expect(history.summary).to start_with('User asked:')
    end

    it 'clears llm_history after archiving' do
      expect(goal.llm_history.length).to eq(3)

      goal.archive_agent_turn!(reason: 'session_timeout')

      expect(goal.reload.llm_history).to be_empty
    end

    it 'clears current_turn_started_at' do
      expect(goal.runtime_state['current_turn_started_at']).to be_present

      goal.archive_agent_turn!(reason: 'session_timeout')

      expect(goal.reload.runtime_state['current_turn_started_at']).to be_nil
    end

    it 'stores metadata correctly' do
      goal.archive_agent_turn!(reason: 'session_timeout')

      history = goal.agent_histories.last
      expect(history.completion_reason).to eq('session_timeout')
      expect(history.message_count).to eq(3)
      expect(history.token_count).to be > 0
      expect(history.started_at).to be_present
      expect(history.completed_at).to be_present
    end

    it 'associates current session thread messages with agent_history' do
      # The before block already creates 12 thread messages
      # All of them should be associated with the new agent_history
      initial_messages = goal.thread_messages.current_session.to_a
      expect(initial_messages.length).to eq(12)
      expect(initial_messages.first.agent_history_id).to be_nil

      goal.archive_agent_turn!(reason: 'session_timeout')

      history = goal.agent_histories.last
      initial_messages.each do |msg|
        expect(msg.reload.agent_history_id).to eq(history.id)
      end
      expect(history.thread_messages.count).to eq(12)
    end

    it 'does nothing if llm_history is empty' do
      goal.update_column(:llm_history, [])

      expect {
        goal.archive_agent_turn!(reason: 'session_timeout')
      }.not_to change(AgentHistory, :count)
    end

    context 'autonomous sessions (UserAgent feed generation)' do
      let(:user_agent) { user.user_agent }

      before do
        user_agent.start_agent_turn_if_needed!
      end

      it 'archives autonomous sessions with tool calls' do
        # Simulate feed generation - has tool calls but no direct user messages
        autonomous_history = [
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'toolu_123', 'content' => 'Search results' }
            ]
          },
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'text', 'text' => 'I found some discoveries.' },
              { 'type' => 'tool_use', 'id' => 'toolu_456', 'name' => 'generate_feed_insight', 'input' => {} }
            ]
          }
        ]
        user_agent.update_column(:llm_history, autonomous_history)

        expect {
          user_agent.archive_agent_turn!(reason: 'feed_generation_complete')
        }.to change(AgentHistory, :count).by(1)

        history = user_agent.agent_histories.last
        expect(history.completion_reason).to eq('feed_generation_complete')
        expect(history.summary).to be_present
      end

      it 'skips archiving autonomous sessions without tool calls' do
        # Session with only simple messages, no tool calls
        user_agent.update_column(:llm_history, [
          { 'role' => 'assistant', 'content' => 'Nothing to do.' }
        ])

        expect {
          user_agent.archive_agent_turn!(reason: 'feed_generation_complete')
        }.not_to change(AgentHistory, :count)

        # But history should still be cleared
        expect(user_agent.reload.llm_history).to be_empty
      end

      it 'allows agent to remember autonomous work via recent_agent_history_summaries' do
        # First: autonomous feed generation creates history
        user_agent.update_column(:llm_history, [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'tool_use', 'id' => 'toolu_123', 'name' => 'web_search', 'input' => { 'query' => 'news' } }
            ]
          },
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'toolu_123', 'content' => 'Found 5 articles' }
            ]
          }
        ])
        user_agent.archive_agent_turn!(reason: 'feed_generation_complete')

        # Then: agent can remember what it did
        summaries = user_agent.recent_agent_history_summaries
        expect(summaries.length).to eq(1)
        expect(summaries.first).to be_present
      end
    end
  end

  describe '#recent_agent_history_summaries' do
    before do
      # Create 10 agent histories with different dates
      10.times do |i|
        goal.agent_histories.create!(
          agent_history: [{ role: 'user', content: "Message #{i}" }],
          summary: "Summary #{i}",
          message_count: 1,
          token_count: 100,
          completed_at: i.days.ago
        )
      end
    end

    it 'returns last 5 summaries by default' do
      summaries = goal.recent_agent_history_summaries
      expect(summaries.length).to eq(5)
    end

    it 'formats summaries with dates' do
      summaries = goal.recent_agent_history_summaries
      expect(summaries.first).to match(/\[.*\] Summary 0/)
    end

    it 'returns most recent first' do
      summaries = goal.recent_agent_history_summaries
      expect(summaries.first).to include('Summary 0')  # Most recent
      expect(summaries.last).to include('Summary 4')   # 5th most recent
    end

    it 'respects custom limit' do
      summaries = goal.recent_agent_history_summaries(limit: 3)
      expect(summaries.length).to eq(3)
    end

    it 'returns empty array if no history' do
      goal.agent_histories.destroy_all
      expect(goal.recent_agent_history_summaries).to eq([])
    end
  end

  describe '#estimate_tokens' do
    it 'estimates tokens roughly (4 chars = 1 token)' do
      messages = [
        { role: 'user', content: 'a' * 400 },  # ~100 tokens
        { role: 'assistant', content: 'b' * 800 }  # ~200 tokens
      ]

      tokens = goal.send(:estimate_tokens, messages)
      expect(tokens).to be_between(250, 350)  # ~300 tokens expected
    end
  end

  describe '#extract_tool_names' do
    it 'extracts unique tool names from history' do
      history = [
        { 'role' => 'assistant', 'tool_calls' => [{ 'name' => 'create_note' }, { 'name' => 'search_notes' }] },
        { 'role' => 'user', 'content' => 'test' },
        { 'role' => 'assistant', 'tool_calls' => [{ 'name' => 'create_note' }] }
      ]

      tools = goal.send(:extract_tool_names, history)
      expect(tools).to match_array(['create_note', 'search_notes'])
    end

    it 'returns empty array if no tool calls' do
      history = [
        { 'role' => 'user', 'content' => 'test' },
        { 'role' => 'assistant', 'content' => 'response' }
      ]

      tools = goal.send(:extract_tool_names, history)
      expect(tools).to eq([])
    end
  end

  describe '#fallback_summary_from_user_messages' do
    it 'extracts user messages' do
      history = [
        { 'role' => 'user', 'content' => 'What are my finances?' },
        { 'role' => 'assistant', 'content' => 'Let me check' },
        { 'role' => 'user', 'content' => 'And savings?' }
      ]

      summary = goal.send(:fallback_summary_from_user_messages, history)
      expect(summary).to eq('User asked: What are my finances? And savings?')
    end

    it 'truncates long messages' do
      history = [
        { 'role' => 'user', 'content' => 'a' * 300 }
      ]

      summary = goal.send(:fallback_summary_from_user_messages, history)
      expect(summary.length).to be <= 215  # "User asked: " + 200 chars + "..."
    end

    it 'provides date fallback if no user messages' do
      history = [
        { 'role' => 'assistant', 'content' => 'test' }
      ]

      summary = goal.send(:fallback_summary_from_user_messages, history)
      expect(summary).to match(/Agent session on/)
    end
  end

  describe 'polymorphic behavior' do
    it 'works with Goal' do
      goal.add_to_llm_history({ 'role' => 'user', 'content' => 'test' })
      goal.start_agent_turn_if_needed!
      create_thread_messages_for_archive(goal)
      goal.archive_agent_turn!(reason: 'test')

      expect(goal.agent_histories.count).to eq(1)
      expect(goal.agent_histories.first.agentable).to eq(goal)
    end

    it 'works with UserAgent' do
      user_agent = user.user_agent || user.create_user_agent!
      user_agent.add_to_llm_history({ 'role' => 'user', 'content' => 'test' })
      user_agent.start_agent_turn_if_needed!
      create_thread_messages_for_archive(user_agent)
      user_agent.archive_agent_turn!(reason: 'test')

      expect(user_agent.agent_histories.count).to eq(1)
      expect(user_agent.agent_histories.first.agentable).to eq(user_agent)
    end

    it 'works with AgentTask' do
      task = create(:agent_task, user: user, goal: goal)
      task.add_to_llm_history({ 'role' => 'user', 'content' => 'test' })
      task.start_agent_turn_if_needed!
      create_thread_messages_for_archive(task)
      task.archive_agent_turn!(reason: 'test')

      expect(task.agent_histories.count).to eq(1)
      expect(task.agent_histories.first.agentable).to eq(task)
    end
  end
end
