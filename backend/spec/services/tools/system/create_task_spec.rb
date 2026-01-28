# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::System::CreateTask, type: :service do
  let(:user) { create(:user) }
  let(:user_agent) { user.user_agent }

  before do
    # Prevent orchestrator from actually running via after_create callback
    allow_any_instance_of(AgentTask).to receive(:start_orchestrator!)
    allow(Streams::Broker).to receive(:publish)
  end

  describe '#extract_inheritable_context (context inheritance)' do
    # Regression test: type must NOT propagate to child tasks.
    # If 'type' leaks into child context_data, the child orchestrator misidentifies
    # its execution mode (e.g. enters feed_generation mode for a research task)
    # and rejects the work. See: Orchestrator#feed_generation? / #check_in_execution?

    def build_tool(context:)
      described_class.new(
        user: user,
        agentable: user_agent,
        context: context
      )
    end

    it 'maps type to origin_type so child orchestrator does not misidentify execution mode' do
      tool = build_tool(context: {
        'type' => 'feed_generation',
        'feed_period' => 'morning',
        'time_of_day' => 'morning',
        'scheduled' => 'true'
      })

      inherited = tool.send(:extract_inheritable_context)

      expect(inherited).not_to have_key('type')
      expect(inherited['origin_type']).to eq('feed_generation')
      expect(inherited['feed_period']).to eq('morning')
      expect(inherited['time_of_day']).to eq('morning')
      expect(inherited['scheduled']).to eq('true')
    end

    it 'does not include origin_type when parent has no type' do
      tool = build_tool(context: { 'feed_period' => 'afternoon' })

      inherited = tool.send(:extract_inheritable_context)

      expect(inherited).not_to have_key('origin_type')
      expect(inherited['feed_period']).to eq('afternoon')
    end

    it 'returns empty hash when context is nil' do
      tool = build_tool(context: nil)

      inherited = tool.send(:extract_inheritable_context)

      expect(inherited).to eq({})
    end

    it 'strips nil values from inherited context' do
      tool = build_tool(context: { 'feed_period' => nil, 'time_of_day' => 'evening' })

      inherited = tool.send(:extract_inheritable_context)

      expect(inherited).not_to have_key('feed_period')
      expect(inherited['time_of_day']).to eq('evening')
    end
  end

  describe 'end-to-end: child task does not enter feed_generation mode' do
    it 'creates a task whose context_data will not trigger feed_generation? in orchestrator' do
      tool = described_class.new(
        user: user,
        agentable: user_agent,
        context: { 'type' => 'feed_generation', 'feed_period' => 'morning', 'time_of_day' => 'morning' }
      )

      result = tool.execute(title: 'Test research', instructions: 'Look into testing patterns')

      expect(result[:success]).to be true

      task = AgentTask.find(result[:task_id])
      # The orchestrator uses context_data['type'] to dispatch execution mode.
      # Child tasks must NOT have 'type' — only 'origin_type' as metadata.
      expect(task.context_data).not_to have_key('type')
      expect(task.context_data['origin_type']).to eq('feed_generation')

      # Verify: if the orchestrator were initialized with this context,
      # it would NOT enter feed_generation mode
      orchestrator = Agents::Orchestrator.new
      orchestrator.instance_variable_set(:@context, task.context_data)
      expect(orchestrator.send(:feed_generation?)).to be false
    end
  end
end
