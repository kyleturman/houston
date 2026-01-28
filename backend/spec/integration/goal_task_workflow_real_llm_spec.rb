# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Goal → Task Workflow with Real LLM', :real_llm do
  before(:each) do
    skip_unless_real_llm_enabled

    # Verify required ENV vars are set
    unless ENV['LLM_AGENTS_MODEL'] && !ENV['LLM_AGENTS_MODEL'].empty?
      skip 'Goal→Task workflow test requires LLM_AGENTS_MODEL to be set'
    end
  end
  
  it 'goal agent creates task from user request' do
    puts "\n🎯 GOAL → TASK WORKFLOW TEST"
    puts "="*80
    
    # Create user and goal
    user = create(:user)
    puts "✅ User created: #{user.id}"
    
    goal = Goal.create!(
      user: user,
      title: "Research Healthy Recipes",
      description: "Find quick and healthy recipes",
      agent_instructions: "When asked to create a task, use the create_task tool. Be concise.",
      status: :working
    )
    
    puts "✅ Goal created: '#{goal.title}'"
    puts "   ID: #{goal.id}"
    
    # User asks to create a task
    message = ThreadMessage.create!(
      agentable: goal,
      source: 'user',
      content: "Create a task to find 3 breakfast recipes under 10 minutes",
      user: user
    )
    
    puts "\n✅ User message: '#{message.content[0..60]}...'"
    
    # Call orchestrator
    puts "\n🤖 Running goal orchestrator..."
    test_start = Time.current
    start_time = Time.current
    
    # Enable debug logging to see what happens
    old_level = Rails.logger.level
    Rails.logger.level = :debug
    
    begin
      orchestrator = Agents::Orchestrator.new
      result = orchestrator.perform(goal.class.name, goal.id, {})
      puts "   Orchestrator result: #{result.inspect}"
    rescue => e
      puts "   ❌ ERROR: #{e.class}: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(10).join("\n   ")}"
      raise
    ensure
      Rails.logger.level = old_level
    end
    
    elapsed = Time.current - start_time
    puts "⏱️  Orchestrator took: #{elapsed.round(2)}s"
    
    # Check if task was created
    goal.reload
    task = goal.agent_tasks.last
    
    puts "\n📊 Results:"
    puts "   Agent messages: #{goal.thread_messages.where(source: 'agent').count}"
    puts "   LLM history entries: #{goal.llm_history.length}"
    puts "   Tasks created: #{goal.agent_tasks.count}"
    
    if task
      puts "\n✅ Task created: '#{task.title}'"
      puts "   Status: #{task.status}"
      puts "   Instructions: #{task.instructions[0..100]}..." if task.instructions
    else
      puts "\n❌ No task created"
      puts "\n📜 Full LLM History:"
      goal.llm_history.each_with_index do |entry, i|
        puts "   [#{i}] #{entry['role']}"
        if entry['content'].is_a?(Array)
          entry['content'].each do |block|
            if block['type'] == 'tool_use'
              puts "      TOOL: #{block['name']} (id: #{block['id']})"
              puts "      INPUT: #{block['input'].inspect}"
            elsif block['type'] == 'tool_result'
              puts "      RESULT: #{block['content'].to_s[0..200]}"
            else
              puts "      #{block['type']}: #{block['text'].to_s[0..100]}"
            end
          end
        else
          puts "      #{entry['content'].to_s[0..200]}"
        end
      end
    end
    
    # Verify task was created
    expect(task).to be_present, "Goal agent should have created a task"
    expect(task.title).to be_present
    
    puts "\n✅ Step 1 Complete: Task created by goal agent"
    puts "   Task status: #{task.status}"
    
    # Step 2: Run task agent to complete the task and create a note
    # Skip if task was cancelled (health monitor cleanup)
    unless task.status == 'cancelled'
    puts "\n🤖 Running task orchestrator..."
    task_start_time = Time.current
    
    begin
      orchestrator = Agents::Orchestrator.new
      orchestrator.perform('AgentTask', task.id, {})
    rescue => e
      puts "   ❌ ERROR: #{e.class}: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(10).join("\n   ")}"
      raise
    end
    
    task_elapsed = Time.current - task_start_time
    puts "⏱️  Task orchestrator took: #{task_elapsed.round(2)}s"
    
    # Check task results
    task.reload
    notes = goal.notes.where("created_at >= ?", task.created_at)
    
    puts "\n📊 Task Results:"
    puts "   Task status: #{task.status}"
    puts "   LLM history entries: #{task.llm_history.length}"
    puts "   Notes created: #{notes.count}"
    
    if notes.any?
      notes.each do |note|
        puts "\n📝 Note: '#{note.title}'"
        puts "   Content length: #{note.content.length} chars"
        puts "   Preview: #{note.content[0..150]}..."
      end
    end
    
    # Verify workflow completed
    expect(notes.count).to be > 0, "Task agent should have created at least one note"
    expect(task.status).to be_in(['completed']), "Task should be completed"
    
    note = notes.first
    expect(note.title).to be_present, "Note should have a title"
    expect(note.content).to be_present, "Note should have content"
    expect(note.content.length).to be > 100, "Note should have substantial content"
    
    # Calculate test cost
    test_cost = LlmCost.where(user: user).where("created_at >= ?", test_start).sum(:cost)
    
    puts "\n✅ COMPLETE WORKFLOW TEST PASSED!"
    puts "   Goal: #{goal.title}"
    puts "   Task: #{task.title} (#{task.status})"
    puts "   Note: #{note.title} (#{note.content.length} chars)"
    puts "\n💰 Total Cost: #{LlmCost.format_cost(test_cost)}"
    puts "="*80
    else
      puts "\n⚠️  Task was cancelled, skipping execution phase"
      puts "="*80
    end
  end
end
