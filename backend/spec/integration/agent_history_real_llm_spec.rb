# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Agent History with Real LLM', :real_llm, type: :integration do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user, title: 'Test Goal', description: 'Testing agent history') }

  before do
    skip 'Set USE_REAL_LLM=true to run (costs ~$0.02-0.05)' unless ENV['USE_REAL_LLM'] == 'true'
  end

  describe 'full session lifecycle with real LLM' do
    it 'summarizes conversation and makes it available in next session' do
      # === SESSION 1: Initial Conversation ===
      puts "\n=== SESSION 1: Initial conversation ==="

      # Simulate a realistic conversation
      conversation = [
        { role: 'user', content: 'What are the best practices for Ruby on Rails testing?' },
        {
          role: 'assistant',
          content: 'Ruby on Rails testing best practices include: 1) Use RSpec for behavior-driven development, 2) Keep tests fast with proper fixtures and factories, 3) Follow the AAA pattern (Arrange, Act, Assert), 4) Use request specs for integration tests, and 5) Mock external services.'
        },
        { role: 'user', content: 'Can you elaborate on mocking external services?' },
        {
          role: 'assistant',
          content: 'Mocking external services in Rails tests helps keep tests fast and reliable. Use tools like WebMock or VCR to stub HTTP requests. VCR records real API responses and replays them in tests, while WebMock allows you to stub responses programmatically. This prevents tests from depending on external API availability and keeps your test suite fast.'
        },
        {
          role: 'assistant',
          tool_calls: [
            { name: 'create_note', function: { arguments: { title: 'Rails Testing', content: 'Key testing practices discussed' } } }
          ]
        }
      ]

      # Add conversation to llm_history
      conversation.each { |msg| goal.add_to_llm_history(msg) }
      goal.start_agent_turn_if_needed!

      seed_thread_messages_for_archive(goal, user: user)

      puts "   ✓ Added #{conversation.length} messages to llm_history"

      # Archive the session (this calls real LLM for summarization)
      puts "   → Calling real LLM to generate summary..."
      goal.archive_agent_turn!(reason: 'session_timeout')

      # Check that archive was created
      expect(goal.agent_histories.count).to eq(1)
      history = goal.agent_histories.last

      puts "   ✓ Summary generated: #{history.summary}"
      puts "   ✓ Message count: #{history.message_count}"
      puts "   ✓ Token estimate: #{history.token_count}"

      # Verify summary quality
      summary = history.summary.downcase
      expect(summary).to be_present
      expect(summary.length).to be > 20  # Should be substantial
      # Summary should mention testing or Rails (the topic)
      expect(summary).to match(/test|rail|mock|rspec|practic/i)

      # Verify llm_history was cleared
      expect(goal.reload.llm_history).to be_empty

      # Verify full conversation was saved
      expect(history.agent_history.length).to eq(conversation.length)
      expect(history.agent_history.first['content']).to include('Ruby on Rails testing')

      # === SESSION 2: Follow-up Conversation with Context ===
      puts "\n=== SESSION 2: Follow-up with agent history context ==="

      # New conversation after time gap
      goal.add_to_llm_history({ role: 'user', content: 'What did we discuss earlier about testing?' })
      goal.start_agent_turn_if_needed!

      # Build context with agent history
      context = Llms::Prompts::Context.agent_history(agentable: goal)

      puts "   ✓ Context includes agent history"
      expect(context).to include('<your_memory>')
      expect(context).to include(history.summary)

      # The summary should provide enough context for follow-up questions
      expect(history.summary).to be_present
      puts "   ✓ Previous summary available for context: #{history.summary[0..100]}..."

      # Clean up
      goal.update_column(:llm_history, [])
    end

    it 'can search archived conversations' do
      # Create multiple archived sessions with different topics
      puts "\n=== Creating archived sessions ==="

      sessions = [
        {
          messages: [
            { role: 'user', content: 'Tell me about Ruby performance optimization' },
            { role: 'assistant', content: 'Ruby performance can be improved through memoization, database query optimization, background jobs, and caching strategies.' }
          ]
        },
        {
          messages: [
            { role: 'user', content: 'How do I implement caching in Rails?' },
            { role: 'assistant', content: 'Rails provides fragment caching, page caching, and action caching. Use Rails.cache for low-level caching with Redis or Memcached backends.' }
          ]
        },
        {
          messages: [
            { role: 'user', content: 'What are Rails security best practices?' },
            { role: 'assistant', content: 'Rails security practices include: strong parameters, SQL injection prevention, CSRF protection, XSS prevention, and keeping gems updated.' }
          ]
        }
      ]

      sessions.each_with_index do |session, i|
        session[:messages].each { |msg| goal.add_to_llm_history(msg) }
        goal.start_agent_turn_if_needed!
        seed_thread_messages_for_archive(goal, user: user)

        puts "   → Archiving session #{i + 1}..."
        goal.archive_agent_turn!(reason: 'session_timeout')
        sleep 0.5  # Ensure different timestamps
      end

      expect(goal.agent_histories.count).to eq(3)
      puts "   ✓ Created #{goal.agent_histories.count} archived sessions"

      # === Search for specific topic ===
      puts "\n=== Searching archived sessions ==="

      # Search for "caching"
      tool = Tools::System::SearchAgentHistory.new(
        user: user,
        goal: goal,
        task: nil,
        agentable: goal
      )

      result = tool.execute(query: 'caching')

      expect(result[:success]).to be true
      expect(result[:observation]).to include('caching')
      puts "   ✓ Search results: #{result[:observation]}"

      # Should find sessions and mark them as matched in full conversation
      # (Search tool displays summaries, but searches full agent_history JSONB)
      expect(result[:observation]).to match(/\[matched in conversation\]|caching/i)
      expect(result[:observation]).to match(/Found \d+ previous session/)

      # Search with timeframe
      recent_result = tool.execute(query: 'security', timeframe: 'last_week')
      expect(recent_result[:success]).to be true
      puts "   ✓ Timeframe search works"

      # Search for non-existent topic
      no_result = tool.execute(query: 'machine learning')
      expect(no_result[:success]).to be true
      expect(no_result[:observation]).to include('No previous sessions found')
      puts "   ✓ No results case handled correctly"
    end

    it 'handles long conversations with token estimation' do
      puts "\n=== Testing token estimation ==="

      # Create a long conversation
      long_conversation = []
      20.times do |i|
        long_conversation << {
          role: 'user',
          content: "This is message number #{i}. " + ('a' * 100)  # Each message ~110 chars
        }
        long_conversation << {
          role: 'assistant',
          content: "Response to message #{i}. " + ('b' * 200)  # Each response ~220 chars
        }
      end

      long_conversation.each { |msg| goal.add_to_llm_history(msg) }
      goal.start_agent_turn_if_needed!
      seed_thread_messages_for_archive(goal, user: user)

      puts "   ✓ Added #{long_conversation.length} messages"

      goal.archive_agent_turn!(reason: 'session_timeout')

      history = goal.agent_histories.last
      puts "   ✓ Token estimate: #{history.token_count}"

      # Rough estimate: 40 messages × ~150 chars avg = 6000 chars / 4 = ~1500 tokens
      expect(history.token_count).to be > 1000
      expect(history.token_count).to be < 5000

      # Summary should be much shorter than full conversation
      expect(history.summary.length).to be < 500
      puts "   ✓ Summary is concise: #{history.summary.length} characters"
    end

    it 'gracefully handles summarization with tool calls' do
      puts "\n=== Testing summarization with tool calls ==="

      # Conversation with mixed content and tool calls (uses shared builders for canonical format)
      mixed_conversation = [
        { role: 'user', content: 'Research best Rails gems for 2025' },
        history_assistant_with_tool_use(
          'Let me search for that.',
          tool_name: 'brave_web_search', tool_id: 'search_1',
          input: { 'query' => 'best Rails gems 2025' }
        ),
        history_tool_result(tool_id: 'search_1', content: 'Search results about Rails gems...'),
        history_assistant_with_tool_use(
          'Based on the search, top Rails gems include Devise for authentication, Sidekiq for background jobs, and RSpec for testing.',
          tool_name: 'create_note', tool_id: 'note_1',
          input: { 'title' => 'Rails Gems 2025', 'content' => 'Top gems list' }
        )
      ]

      mixed_conversation.each { |msg| goal.add_to_llm_history(msg) }
      goal.start_agent_turn_if_needed!

      puts "   ✓ Added conversation with #{mixed_conversation.length} messages (including tool calls)"

      goal.archive_agent_turn!(reason: 'feed_generation_complete')

      history = goal.agent_histories.last
      puts "   ✓ Summary: #{history.summary}"

      # Summary should still be coherent despite tool calls
      expect(history.summary).to be_present
      expect(history.summary).to match(/gem|rail|devise|sidekiq|rspec/i)
      expect(history.completion_reason).to eq('feed_generation_complete')

      puts "   ✓ Tool calls handled correctly in summarization"
    end
  end

  describe 'UserAgent agent history' do
    let(:user_agent) { user.user_agent || create(:user_agent, user: user) }

    it 'works with UserAgent conversations' do
      skip 'Set USE_REAL_LLM=true to run (costs ~$0.01)' unless ENV['USE_REAL_LLM'] == 'true'

      puts "\n=== Testing UserAgent agent history ==="

      # Simulate cross-goal conversation with tool use (required for autonomous archiving)
      conversation = [
        { role: 'user', content: 'How are my goals progressing overall?' },
        history_assistant_with_tool_use(
          'Let me check your progress.',
          tool_name: 'send_message', tool_id: 'tool_1',
          input: { 'text' => 'Your fitness goal shows good momentum with 3 workouts this week. The reading goal needs attention - no updates in 5 days.' }
        )
      ]

      conversation.each { |msg| user_agent.add_to_llm_history(msg) }
      user_agent.start_agent_turn_if_needed!

      user_agent.archive_agent_turn!(reason: 'feed_generation_complete')

      history = user_agent.agent_histories.last
      puts "   ✓ UserAgent summary: #{history.summary}"

      expect(history.summary).to be_present
      expect(history.summary).to match(/goal|progress|fitness|reading/i)

      # Verify UserAgent can retrieve history
      summaries = user_agent.recent_agent_history_summaries
      expect(summaries).not_to be_empty
      puts "   ✓ UserAgent history retrievable"
    end
  end
end
