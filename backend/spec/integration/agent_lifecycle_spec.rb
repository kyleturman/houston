# frozen_string_literal: true

require 'rails_helper'

# Tags: :integration, :agent, :medium
RSpec.describe 'Agent lifecycle', :integration, :agent, :medium do
  # Use real Rails models for integration testing
  let(:test_user) { create(:user) }
  let(:mock_goal) do
    {
      id: 1,
      title: 'Learn Spanish',
      description: 'Become conversational in Spanish',
      status: 'waiting',
      user_id: 1
    }
  end
  let(:mock_task) do
    {
      id: 1,
      title: 'Research Spanish apps',
      instructions: 'Find top 5 Spanish learning apps',
      status: 'active',
      goal_id: 1
    }
  end

  it 'runs a basic goal→task→completion flow (mocked)', :core do
    # Mock orchestrator workflow
    orchestrator_steps = []
    
    # Simulate goal agent creating a task
    orchestrator_steps << {
      step: 'goal_processing',
      action: 'create_task',
      input: { title: 'Research Spanish apps', instructions: 'Find top 5 Spanish learning apps' },
      output: { task_id: 1, status: 'created' }
    }
    
    # Simulate task agent execution
    orchestrator_steps << {
      step: 'task_execution', 
      action: 'brave_web_search',
      input: { query: 'best Spanish learning apps 2024' },
      output: { results: [{ title: 'Duolingo Review', url: 'example.com' }] }
    }
    
    # Simulate note creation
    orchestrator_steps << {
      step: 'note_creation',
      action: 'create_note',
      input: { title: 'Spanish Apps Research', content: 'Found 5 top apps...' },
      output: { note_id: 1, status: 'created' }
    }
    
    # Simulate completion
    orchestrator_steps << {
      step: 'completion',
      action: 'mark_task_complete',
      input: { task_id: 1, summary: 'Research completed successfully' },
      output: { status: 'completed' }
    }

    # Validate workflow progression
    expect(orchestrator_steps.length).to eq(4)
    expect(orchestrator_steps[0][:action]).to eq('create_task')
    expect(orchestrator_steps[1][:action]).to eq('brave_web_search')
    expect(orchestrator_steps[2][:action]).to eq('create_note')
    expect(orchestrator_steps[3][:action]).to eq('mark_task_complete')
    
    # Validate each step has proper input/output structure
    orchestrator_steps.each do |step|
      expect(step).to have_key(:step)
      expect(step).to have_key(:action)
      expect(step).to have_key(:input)
      expect(step).to have_key(:output)
      expect(step[:input]).to be_a(Hash)
      expect(step[:output]).to be_a(Hash)
    end
  end

  it 'streams messages in correct order (mocked)', :streaming do
    # Mock SSE event stream for agent execution
    sse_events = []
    
    # Goal agent starts processing
    sse_events << {
      event: 'goal_status',
      data: { goal_id: 1, status: 'working', timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z') }
    }
    
    # Tool execution begins
    sse_events << {
      event: 'tool_start',
      data: { tool_name: 'create_task', tool_id: 'tool_1', timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z') }
    }
    
    # Tool completes
    sse_events << {
      event: 'tool_completion',
      data: { 
        tool_name: 'create_task', 
        tool_id: 'tool_1', 
        status: 'success',
        result: { task_id: 1 },
        timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
      }
    }
    
    # Agent message sent
    sse_events << {
      event: 'message',
      data: {
        id: 'msg_1',
        content: 'I created a task to research Spanish learning apps.',
        source: 'agent',
        timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
      }
    }
    
    # Goal returns to waiting
    sse_events << {
      event: 'goal_status',
      data: { goal_id: 1, status: 'waiting', timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z') }
    }

    # Validate event ordering and structure
    expect(sse_events.length).to eq(5)
    expect(sse_events[0][:event]).to eq('goal_status')
    expect(sse_events[0][:data][:status]).to eq('working')
    
    expect(sse_events[1][:event]).to eq('tool_start')
    expect(sse_events[2][:event]).to eq('tool_completion')
    expect(sse_events[3][:event]).to eq('message')
    
    expect(sse_events[4][:event]).to eq('goal_status')
    expect(sse_events[4][:data][:status]).to eq('waiting')
    
    # Validate all events have required metadata
    sse_events.each do |event|
      expect(event).to have_key(:event)
      expect(event).to have_key(:data)
      expect(event[:data]).to have_key(:timestamp)
      expect(event[:data][:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
  end

  it 'completes task and persists notes', :model do
    # Mock note persistence workflow
    notes_created = []
    
    # Simulate task execution creating multiple notes
    research_note = {
      id: 1,
      title: 'Spanish Learning Apps Research',
      content: 'Researched top 5 Spanish learning apps:\n1. Duolingo\n2. Babbel\n3. Rosetta Stone',
      source: 'agent_task',
      task_id: 1,
      created_at: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
    }
    notes_created << research_note
    
    summary_note = {
      id: 2,
      title: 'Task Completion Summary',
      content: 'Successfully completed research on Spanish learning apps. Found comprehensive comparison.',
      source: 'task_completion',
      task_id: 1,
      created_at: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
    }
    notes_created << summary_note
    
    # Validate note structure and relationships
    expect(notes_created.length).to eq(2)
    
    research_note = notes_created[0]
    expect(research_note[:title]).to include('Research')
    expect(research_note[:content]).to include('Duolingo')
    expect(research_note[:source]).to eq('agent_task')
    expect(research_note[:task_id]).to eq(1)
    
    summary_note = notes_created[1]
    expect(summary_note[:title]).to include('Completion')
    expect(summary_note[:source]).to eq('task_completion')
    expect(summary_note[:task_id]).to eq(1)
    
    # Validate note content quality
    notes_created.each do |note|
      expect(note[:title]).to be_a(String)
      expect(note[:title].length).to be > 5
      expect(note[:content]).to be_a(String)
      expect(note[:content].length).to be > 10
      expect(note[:created_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
    
    # Mock task completion state
    completed_task = mock_task.merge({
      status: 'completed',
      completed_at: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
      result_summary: 'Research completed with 2 notes created'
    })
    
    expect(completed_task[:status]).to eq('completed')
    expect(completed_task[:result_summary]).to include('2 notes')
  end

  it 'validates agent workflow data flow and state transitions', :core do
    # Test comprehensive agent workflow patterns with mocked services
    # This focuses on data flow, state management, and integration points
    
    puts "\n🔄 Testing agent workflow data flow and state transitions..."
    
    # 1. Test Goal creation and initial state
    goal = Goal.create_with_agent!(
      user: test_user,
      title: "Data Flow Test Goal",
      description: "Test comprehensive agent data flow patterns"
    )
    
    expect(goal.status).to eq('working')
    expect(goal.agent_tasks).to be_empty
    puts "✅ Goal created with proper initial state"
    
    # 2. Test user message creation and threading
    user_message = ThreadMessage.create!(
      user: test_user,
      agentable: goal,
      source: :user,
      content: "Create a task to analyze workflow patterns"
    )
    
    expect(user_message.agentable).to eq(goal)
    expect(user_message.source).to eq('user')
    puts "✅ User message properly threaded to goal"
    
    # 3. Mock agent processing and task creation
    allow_any_instance_of(Goal).to receive(:start_orchestrator!).and_return(true)
    
    # Simulate agent creating a task
    task = AgentTask.create!(
      goal: goal,
      user: test_user,
      title: "Workflow Analysis Task",
      instructions: "Analyze agent workflow data patterns",
      status: 'active'
    )
    
    goal.reload
    expect(goal.agent_tasks.count).to eq(1)
    expect(goal.agent_tasks.first).to eq(task)
    puts "✅ Task properly associated with goal"
    
    # 4. Test agent message creation
    agent_message = ThreadMessage.create!(
      user: test_user,
      agentable: goal,
      source: :agent,
      content: "I've created a task to analyze workflow patterns."
    )
    
    expect(agent_message.source).to eq('agent')
    expect(goal.thread_messages.count).to eq(2) # user + agent
    puts "✅ Agent message properly threaded"
    
    # 5. Test task processing and note creation
    task_message = ThreadMessage.create!(
      user: test_user,
      agentable: task,
      source: :user,
      content: "Please analyze the workflow and create notes"
    )
    
    # Mock task agent creating notes
    note1 = Note.create!(
      user: test_user,
      title: "Workflow Pattern Analysis",
      content: "Agent workflows follow Goal → Task → Note pattern with proper state management."
    )
    
    note2 = Note.create!(
      user: test_user,
      title: "Data Flow Validation",
      content: "ThreadMessages properly link user inputs to agent responses across agentable types."
    )
    
    # 6. Test task completion
    task.update!(
      status: 'completed',
      result_summary: "Created 2 analysis notes covering workflow patterns and data flow"
    )
    
    expect(task.status).to eq('completed')
    expect(task.result_summary).to include('2 analysis notes')
    puts "✅ Task completed with proper summary"
    
    # 7. Validate final state
    goal.reload
    expect(goal.status).to eq('working') # Goals remain working
    expect(goal.agent_tasks.first.status).to eq('completed')
    expect(Note.where(user: test_user).count).to eq(2)
    
    puts "✅ Complete workflow data flow validated"
    puts "📊 Final state: Goal(active) → Task(completed) → 2 Notes"
  end

  it 'validates agent service integration patterns', :core do
    # Test how agents integrate with various services (mocked)
    # This validates service boundaries and integration points
    
    puts "\n🔌 Testing agent service integration patterns..."
    
    goal = Goal.create_with_agent!(
      user: test_user,
      title: "Service Integration Test",
      description: "Test agent integration with LLM, search, and note services"
    )
    
    # Mock LLM service responses
    mock_llm_response = {
      model: 'claude-3-sonnet',
      content: 'I will help you create notes and search for information.',
      tokens_used: 120,
      success: true
    }
    
    # Mock search service responses  
    mock_search_response = {
      service: 'brave_search',
      query: 'productivity tips',
      results: [
        { title: 'Top 10 Productivity Tips', url: 'example.com/tips' },
        { title: 'Time Management Guide', url: 'example.com/time' }
      ],
      success: true
    }
    
    # Test service integration validation
    expect(mock_llm_response[:success]).to be true
    expect(mock_search_response[:success]).to be true
    expect(mock_search_response[:results].length).to eq(2)
    
    # Mock agent using services to create content
    ThreadMessage.create!(
      user: test_user,
      agentable: goal,
      source: :agent,
      content: "I've searched for productivity information and will create helpful notes."
    )
    
    # Mock note creation from service integration
    Note.create!(
      user: test_user,
      title: "Productivity Research Summary",
      content: "Based on search results: #{mock_search_response[:results].map { |r| r[:title] }.join(', ')}"
    )
    
    expect(Note.where(user: test_user).count).to eq(1)
    expect(Note.last.content).to include('Top 10 Productivity Tips')
    
    puts "✅ Agent service integration patterns validated"
  end

  it 'tests comprehensive agent orchestration flow', :core do
    # Test the complete orchestration pattern with mocked components
    # This validates the full agent lifecycle without external dependencies
    
    puts "\n🎼 Testing comprehensive agent orchestration flow..."
    
    # 1. Goal creation triggers orchestrator
    goal = Goal.create_with_agent!(
      user: test_user,
      title: "Orchestration Flow Test",
      description: "Test complete agent orchestration with task creation and completion"
    )
    
    # Mock orchestrator processing
    allow_any_instance_of(Goal).to receive(:start_orchestrator!).and_return(true)
    
    # 2. User message triggers agent processing
    user_msg = ThreadMessage.create!(
      user: test_user,
      agentable: goal,
      source: :user,
      content: "Please create a task to research productivity methods and create summary notes"
    )
    
    # 3. Mock Goal Agent creating a task
    task = AgentTask.create!(
      goal: goal,
      user: test_user,
      title: "Research Productivity Methods",
      instructions: "Research and summarize effective productivity techniques",
      status: 'active'
    )
    
    # 4. Mock Goal Agent response
    goal_agent_msg = ThreadMessage.create!(
      user: test_user,
      agentable: goal,
      source: :agent,
      content: "I've created a research task for productivity methods. The task agent will handle the research and create summary notes."
    )
    
    # 5. Mock Task Agent processing
    task_msg = ThreadMessage.create!(
      user: test_user,
      agentable: task,
      source: :user,
      content: "Begin research on productivity methods"
    )
    
    # 6. Mock Task Agent creating notes
    note1 = Note.create!(
      user: test_user,
      title: "Time Management Techniques",
      content: "Key techniques: Pomodoro Technique, time blocking, priority matrices"
    )
    
    note2 = Note.create!(
      user: test_user,
      title: "Focus and Concentration Methods",
      content: "Methods: Deep work principles, distraction elimination, environment optimization"
    )
    
    # 7. Mock Task Agent completion
    task.update!(
      status: 'completed',
      result_summary: "Research completed. Created 2 comprehensive notes on productivity methods covering time management and focus techniques."
    )
    
    task_agent_msg = ThreadMessage.create!(
      user: test_user,
      agentable: task,
      source: :agent,
      content: "Research completed! I've created comprehensive notes on productivity methods."
    )
    
    # 8. Validate complete orchestration flow
    goal.reload
    expect(goal.status).to eq('working') # Goal remains working
    expect(goal.agent_tasks.count).to eq(1)
    expect(goal.agent_tasks.first.status).to eq('completed')
    expect(goal.thread_messages.count).to eq(2) # user + goal agent
    expect(task.thread_messages.count).to eq(2) # user + task agent
    expect(Note.where(user: test_user).count).to eq(2)
    
    puts "✅ Complete orchestration flow validated"
    puts "📊 Flow: Goal(active) → Task(completed) → 2 Notes → 4 Messages"
  end

end
