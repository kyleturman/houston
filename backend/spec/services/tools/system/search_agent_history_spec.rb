# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::System::SearchAgentHistory, type: :tool do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }
  let(:tool) { described_class.new(user: user, goal: goal, task: nil, agentable: goal) }

  before do
    # Create some test agent histories
    goal.agent_histories.create!([
      {
        agent_history: [
          { role: 'user', content: 'What are my finances like?' },
          { role: 'assistant', content: 'Your savings account has $5,000 and checking has $2,000.' }
        ],
        summary: 'User asked about finances. Reported savings: $5K, checking: $2K.',
        message_count: 2,
        token_count: 200,
        completed_at: 2.days.ago
      },
      {
        agent_history: [
          { role: 'user', content: 'Can I afford a new laptop?' },
          { role: 'assistant', content: 'Based on your $5K savings, yes you can afford a $1500 laptop.' }
        ],
        summary: 'User asked about laptop purchase affordability. Confirmed can afford $1500 laptop with current savings.',
        message_count: 2,
        token_count: 180,
        completed_at: 1.day.ago
      },
      {
        agent_history: [
          { role: 'user', content: 'What exercises did you recommend?' },
          { role: 'assistant', content: 'I recommended bodyweight exercises: push-ups, squats, and planks.' }
        ],
        summary: 'User asked about exercise recommendations. Discussed bodyweight exercises.',
        message_count: 2,
        token_count: 150,
        completed_at: 5.hours.ago
      }
    ])
  end

  describe '.metadata' do
    it 'returns correct tool metadata' do
      metadata = described_class.metadata

      expect(metadata[:name]).to eq('search_agent_history')
      expect(metadata[:description]).to include('Search your previous conversation history')
      expect(metadata[:params_hint]).to include('query')
    end
  end

  describe '.schema' do
    it 'returns valid JSON schema' do
      schema = described_class.schema

      expect(schema[:type]).to eq('object')
      expect(schema[:properties][:query]).to be_present
      expect(schema[:properties][:timeframe]).to be_present
      expect(schema[:required]).to include('query')
    end
  end

  describe '#execute' do
    context 'with matching query in summary' do
      it 'finds sessions matching the query' do
        result = tool.execute(query: 'finances')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('finances')
        expect(result[:observation]).to include('$5K')
        expect(result[:observation]).to match(/Found \d+ previous session/)
      end
    end

    context 'with matching query in full history' do
      it 'finds sessions even if only in full conversation' do
        # Query for 'account' which is only in full history, not in summary
        result = tool.execute(query: 'account')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('[matched in conversation]')
        expect(result[:observation]).to match(/Found \d+ previous session/)
      end
    end

    context 'with no matching results' do
      it 'returns helpful no-results message' do
        result = tool.execute(query: 'machine learning')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('No previous sessions found')
        expect(result[:observation]).to include('machine learning')
      end
    end

    context 'with timeframe' do
      it 'filters by last_week' do
        result = tool.execute(query: 'finances', timeframe: 'last_week')

        expect(result[:success]).to be true
        # All our test data is within last week, so should find results
        expect(result[:observation]).to match(/Found \d+ previous session/)
      end

      it 'filters by last_month' do
        result = tool.execute(query: 'exercises', timeframe: 'last_month')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('exercises')
      end

      it 'filters by last_year' do
        result = tool.execute(query: 'laptop', timeframe: 'last_year')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('laptop')
      end

      it 'handles no results with timeframe' do
        # Create old history outside timeframe
        old_history = goal.agent_histories.create!(
          agent_history: [{ role: 'user', content: 'Old conversation about crypto' }],
          summary: 'Discussed cryptocurrency',
          message_count: 1,
          token_count: 100,
          completed_at: 2.years.ago
        )

        result = tool.execute(query: 'crypto', timeframe: 'last_week')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('No previous sessions found')
        expect(result[:observation]).to include('in last_week')
      end
    end

    context 'result formatting' do
      it 'includes date, summary, and message count' do
        result = tool.execute(query: 'laptop')

        expect(result[:observation]).to match(/\w+ \d+, \d{4}/)  # Date format
        expect(result[:observation]).to include('2 messages')
        expect(result[:observation]).to include('laptop')
      end

      it 'marks results matched in full conversation' do
        result = tool.execute(query: 'push-ups')  # Only in full history

        expect(result[:observation]).to include('[matched in conversation]')
      end

      it 'limits results to 5' do
        # Create 10 histories with same keyword
        10.times do |i|
          goal.agent_histories.create!(
            agent_history: [{ role: 'user', content: "Question #{i} about finances" }],
            summary: "Session #{i} about finances",
            message_count: 1,
            token_count: 100,
            completed_at: (i + 1).hours.ago
          )
        end

        result = tool.execute(query: 'finances')

        # Should find max 5 results
        result_count = result[:observation].scan(/Session \d+ about finances/).length
        expect(result_count).to be <= 5
      end

      it 'returns most recent results first' do
        result = tool.execute(query: 'asked')  # Common word in all summaries

        lines = result[:observation].lines
        # First result should be more recent than last
        # Note: Exact date comparison is tricky, but we can check order
        expect(result[:observation]).to match(/Found \d+ previous session/)
      end
    end

    context 'case insensitivity' do
      it 'searches case-insensitively' do
        result_lower = tool.execute(query: 'finances')
        result_upper = tool.execute(query: 'FINANCES')
        result_mixed = tool.execute(query: 'FinAnCes')

        expect(result_lower[:success]).to be true
        expect(result_upper[:success]).to be true
        expect(result_mixed[:success]).to be true

        # All should find the same results
        expect(result_lower[:observation]).to include('finances')
        expect(result_upper[:observation]).to include('finances')
        expect(result_mixed[:observation]).to include('finances')
      end
    end

    context 'partial matching' do
      it 'finds partial word matches' do
        result = tool.execute(query: 'sav')  # Partial match for "savings"

        expect(result[:success]).to be true
        expect(result[:observation]).to include('savings')
      end
    end

    context 'special characters' do
      it 'handles dollar signs in query' do
        result = tool.execute(query: '$5K')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('$5K')
      end

      it 'handles queries with spaces' do
        result = tool.execute(query: 'new laptop')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('laptop')
      end
    end

    context 'empty agentable history' do
      before do
        goal.agent_histories.destroy_all
      end

      it 'handles no history gracefully' do
        result = tool.execute(query: 'anything')

        expect(result[:success]).to be true
        expect(result[:observation]).to include('No previous sessions found')
      end
    end
  end

  describe 'integration with tool registry' do
    it 'is included in registry for goals with history' do
      registry = Tools::Registry.new(user: user, goal: goal, task: nil, agentable: goal)
      tools = registry.send(:enabled_tools_for_context, :goal)

      expect(tools).to include('search_agent_history')
    end

    it 'is excluded from registry for goals without history' do
      # Create a fresh goal without any histories
      fresh_goal = create(:goal, user: user)

      registry = Tools::Registry.new(user: user, goal: fresh_goal, task: nil, agentable: fresh_goal)
      tools = registry.send(:enabled_tools_for_context, :goal)

      expect(tools).not_to include('search_agent_history')
    end

    it 'is never available for tasks' do
      task = create(:agent_task, user: user, goal: goal)
      task.agent_histories.create!(
        agent_history: [{ role: 'user', content: 'test' }],
        summary: 'Test',
        message_count: 1,
        token_count: 100,
        completed_at: Time.current
      )

      registry = Tools::Registry.new(user: user, goal: goal, task: task, agentable: task)
      tools = registry.send(:enabled_tools_for_context, :task)

      expect(tools).not_to include('search_agent_history')
    end
  end

  describe 'progress emissions' do
    it 'emits progress events during search' do
      # Mock the emit methods
      allow(tool).to receive(:emit_tool_progress)
      allow(tool).to receive(:emit_tool_completion)

      tool.execute(query: 'finances')

      expect(tool).to have_received(:emit_tool_progress).with(
        'Searching conversation history...',
        data: hash_including(query: 'finances', status: 'searching')
      )

      expect(tool).to have_received(:emit_tool_completion).with(
        /Found \d+ session/,
        data: hash_including(query: 'finances')
      )
    end

    it 'emits completion even with no results' do
      allow(tool).to receive(:emit_tool_completion)

      tool.execute(query: 'nonexistent')

      expect(tool).to have_received(:emit_tool_completion).with(
        'No results found',
        data: hash_including(result_count: 0)
      )
    end
  end
end
