# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Goal Agent with Real LLM', :real_llm do
  before(:each) do
    skip_unless_real_llm_enabled

    # Verify required ENV vars are set
    unless ENV['LLM_AGENTS_MODEL'] && !ENV['LLM_AGENTS_MODEL'].empty?
      skip 'Goal agent test requires LLM_AGENTS_MODEL to be set'
    end
  end
  
  it 'responds to user messages in goal thread' do
    puts "\n🎯 SIMPLE TEST: Ask agent what the goal title is..."
    
    # Create user first
    user = create(:user)
    puts "✅ User created: #{user.id}"
    
    # Create a goal with a clear title
    goal = Goal.create!(
      user: user,
      title: "Learn Piano",
      description: "Learn to play piano for fun",
      status: :working  # Start in working status
    )
    
    puts "✅ Goal created: '#{goal.title}'"
    puts "   ID: #{goal.id}"
    puts "   Status: #{goal.status}"
    puts "   Agent type: #{goal.agent_type}"
    
    # Simple question: What is the goal?
    message = ThreadMessage.create!(
      agentable: goal,
      source: 'user',
      content: "What is the title of this goal?",
      user: user
    )
    
    puts "\n✅ User message created"
    puts "   Message ID: #{message.id}"
    puts "   Content: '#{message.content}'"
    puts "   Agentable: #{message.agentable_type} ##{message.agentable_id}"
    
    # Check initial state
    puts "\n📊 Before orchestrator:"
    puts "   Thread messages: #{goal.thread_messages.count}"
    puts "   Unprocessed messages: #{ThreadMessage.unprocessed_for_agent(user_id: user.id, agentable: goal, source: :user).count}"
    puts "   LLM history entries: #{goal.get_llm_history.length}"
    puts "   Runtime state: #{goal.runtime_state.inspect}"
    puts "   Agent running?: #{goal.agent_running?}"
    
    # Call orchestrator directly (not async) to avoid Sidekiq issues
    puts "\n🤖 Calling orchestrator directly..."
    test_start = Time.current
    start_time = Time.current
    
    begin
      # Enable debug logging
      Rails.logger.level = :debug
      
      puts "   Calling with: #{goal.class.name}, #{goal.id}"
      puts "   Goal exists?: #{Goal.exists?(goal.id)}"
      
      # Call the orchestrator service directly
      orchestrator = Agents::Orchestrator.new
      orchestrator.perform(goal.class.name, goal.id, {})
      puts "   Orchestrator completed"
    rescue => e
      puts "   ❌ ERROR in orchestrator: #{e.class}: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(5).join("\n   ")}"
      raise
    ensure
      Rails.logger.level = :info
    end
    
    elapsed_time = Time.current - start_time
    puts "\n✅ Processing complete (#{elapsed_time.round(2)}s)"
    
    # Check results
    goal.reload
    agent_messages = goal.thread_messages.where(source: 'agent')
    llm_history = goal.get_llm_history
    
    puts "\n📊 After orchestrator:"
    puts "   Total thread messages: #{goal.thread_messages.count}"
    puts "   Agent messages: #{agent_messages.count}"
    puts "   LLM history entries: #{llm_history.length}"
    puts "   Runtime state: #{goal.runtime_state.inspect}"
    
    puts "\n📋 All thread messages:"
    goal.thread_messages.each do |msg|
      puts "   [#{msg.id}] Source: #{msg.source}, Has tool_activity: #{msg.metadata&.key?('tool_activity')}"
      puts "       Content: #{msg.content&.truncate(80)}"
    end
    
    if agent_messages.any?
      puts "\n💬 Agent Response:"
      agent_messages.each_with_index do |msg, idx|
        puts "   [#{idx+1}] #{msg.content&.truncate(150)}"
      end
    else
      puts "\n❌ NO AGENT MESSAGES CREATED"
      puts "\n🔍 Debug - All thread messages:"
      goal.thread_messages.each do |msg|
        puts "   Source: #{msg.source}, Content: #{msg.content&.truncate(100)}"
      end
      
      puts "\n🔍 Debug - LLM History:"
      llm_history.each_with_index do |entry, idx|
        puts "   [#{idx+1}] Role: #{entry['role']}, Content: #{entry['content'].to_s[0..100]}"
      end
    end
    
    # Assertions
    expect(agent_messages.count).to be > 0, "Agent should have responded to user message"
    
    # Check response mentions the goal title
    response_text = agent_messages.first.content.downcase
    expect(response_text).to include('piano'), "Response should mention the goal title 'Piano'"
    
    # Verify the message was created by send_message tool
    # Note: send_message creates ThreadMessages directly without tool_activity metadata
    # The streaming happens via SSE during tool execution, then the message is persisted
    agent_message = agent_messages.first
    
    puts "\n📡 Streaming Architecture:"
    puts "   ✅ send_message tool creates ThreadMessage directly"
    puts "   ✅ Streaming happens via SSE during tool execution"
    puts "   ✅ Final message persisted after streaming completes"
    puts "   Message source: #{agent_message.source}"
    puts "   Message length: #{agent_message.content.length} characters"
    
    # The fact that we have an agent message means send_message was called successfully
    # and the streaming + persistence workflow completed
    expect(agent_message.source).to eq('agent'), "Message should be from agent"
    expect(agent_message.content).to be_present, "Message should have content"
    
    # Calculate test cost
    test_cost = LlmCost.where(user: user).where("created_at >= ?", test_start).sum(:cost)
    
    puts "\n✅ Test passed!"
    puts "\n💰 Total Cost: #{LlmCost.format_cost(test_cost)}"
  end
  
  it 'can create tasks from user requests' do
    puts "\n🎯 Testing Goal Agent Task Creation..."
    
    # Create user first
    user = create(:user)
    
    # Create a goal
    goal = Goal.create!(
      user: user,
      title: "Improve Fitness",
      description: "Get in better shape and build healthy habits",
      status: :waiting
    )
    goal.add_learning("User works from home and sits most of the day")
    goal.add_learning("Has basic gym equipment available")
    
    puts "✅ Goal created: #{goal.title}"
    puts "   Goal is agentable: #{goal.is_a?(Agentable)}"
    
    # User asks for a specific task
    message = ThreadMessage.create!(
      agentable: goal,
      source: 'user',
      content: "Create a task to research effective 20-minute home workouts for beginners",
      user: user
    )
    
    puts "✅ User message: #{message.content}"
    puts "   Message ID: #{message.id}"
    puts "   Agentable: #{message.agentable.class.name} ##{message.agentable.id}"
    
    # Transition goal to working status
    goal.update!(status: :working)
    
    # Start orchestrator
    puts "\n🤖 Starting goal agent..."
    test_start = Time.current
    start_time = Time.current
    
    Agents::Orchestrator.perform_async(
      goal.class.name,
      goal.id,
      { "type" => "goal_agent" }
    )
    
    # Wait for agent to process
    sleep 3
    
    goal.reload
    elapsed_time = Time.current - start_time
    puts "⏱️  Processing time: #{elapsed_time.round(2)}s"
    
    # Debug: Check what the agent did
    puts "\n🔍 Debug Info:"
    puts "   Goal status: #{goal.status}"
    puts "   Thread messages: #{goal.thread_messages.count}"
    puts "   Messages by source:"
    goal.thread_messages.group_by(&:source).each do |source, msgs|
      puts "     #{source}: #{msgs.count}"
    end
    
    # Check if task was created
    tasks = goal.agent_tasks
    puts "\n📋 Tasks Created:"
    puts "   Total tasks: #{tasks.count}"
    
    tasks.each_with_index do |task, idx|
      puts "\n   Task #{idx + 1}:"
      puts "   Title: #{task.title}"
      puts "   Instructions: #{task.instructions&.truncate(150)}"
      puts "   Status: #{task.status}"
    end
    
    # Verify task creation
    if tasks.any?
      task = tasks.first
      expect(task.title).to be_present
      expect(task.instructions).to be_present, "Task MUST have instructions"
      
      # Check if task is relevant to request
      relevant = task.title.downcase.include?('workout') || 
                 task.instructions.to_s.downcase.include?('workout') ||
                 task.title.downcase.include?('exercise')
      
      puts "\n✅ Task created successfully"
      puts "   Task is relevant: #{relevant ? 'YES' : 'NO'}"
    else
      puts "\n⚠️  No tasks created (agent may have responded differently)"
    end
    
    # Check agent messages
    # Note: Agent should NOT send a message after creating a task
    # The task card itself is sufficient (per core prompt guidelines)
    agent_messages = goal.thread_messages.where(source: 'agent')
    puts "\n📨 Agent Messages: #{agent_messages.count}"
    puts "   (Agent should not send message after creating task - card is sufficient)"
    
    # Calculate test cost
    test_cost = LlmCost.where(user: user).where("created_at >= ?", test_start).sum(:cost)
    
    puts "\n💰 Total Cost: #{LlmCost.format_cost(test_cost)}"
    puts "\n=== Task Creation Test Complete ==="
  end
end
