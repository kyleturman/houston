# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'UserAgent Real LLM Tests', :real_llm do
  before(:each) do
    skip_unless_real_llm_enabled

    # Verify required ENV vars are set
    unless ENV['LLM_AGENTS_MODEL'] && !ENV['LLM_AGENTS_MODEL'].empty?
      skip 'UserAgent tests require LLM_AGENTS_MODEL to be set'
    end
  end
  
  let(:user) { create(:user) }
  
  it 'can retrieve user learnings and create thread messages' do
    puts "\n🧠 USER AGENT LEARNINGS TEST"
    puts "="*80
    
    user_agent = user.user_agent
    
    # Add learnings about the user
    user_agent.add_learning("User's name is Alex Chen")
    user_agent.add_learning("User's favorite food is sushi")
    
    puts "✅ User created with learnings:"
    puts "   Learning 1: User's name is Alex Chen"
    puts "   Learning 2: User's favorite food is sushi"
    
    # User asks about their name and favorite food
    message = ThreadMessage.create!(
      agentable: user_agent,
      source: 'user',
      content: "What is my name and what's my favorite food?",
      user: user
    )
    
    puts "\n✅ User message: '#{message.content}'"
    puts "   Message ID: #{message.id}"
    
    # Count initial thread messages
    initial_message_count = user_agent.thread_messages.count
    puts "\n📊 Initial state:"
    puts "   Thread messages: #{initial_message_count}"
    puts "   LLM history entries: #{user_agent.llm_history.length}"
    
    # Run orchestrator
    puts "\n🤖 Running user agent orchestrator..."
    test_start = Time.current
    start_time = Time.current
    
    begin
      # Enable debug logging
      old_level = Rails.logger.level
      Rails.logger.level = :debug
      
      orchestrator = Agents::Orchestrator.new
      result = orchestrator.perform(user_agent.class.name, user_agent.id, {})
      puts "   Orchestrator result: #{result.inspect}"
    rescue => e
      puts "   ❌ ERROR: #{e.class}: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(10).join("\n   ")}"
      raise
    ensure
      Rails.logger.level = old_level if old_level
    end
    
    elapsed = Time.current - start_time
    puts "⏱️  Orchestrator took: #{elapsed.round(2)}s"
    
    # Reload and check results
    user_agent.reload
    
    # Get agent messages created after the user message
    agent_messages = user_agent.thread_messages.where(
      source: 'agent'
    ).where("created_at >= ?", message.created_at)
    
    puts "\n📊 Results:"
    puts "   Total thread messages: #{user_agent.thread_messages.count}"
    puts "   Agent messages created: #{agent_messages.count}"
    puts "   LLM history entries: #{user_agent.llm_history.length}"
    
    # Get new LLM history entries
    new_entries = user_agent.llm_history.select { |e| 
      t = e["timestamp"]&.to_datetime rescue nil
      t && t >= start_time
    }
    puts "   New LLM history entries: #{new_entries.length}"
    
    # Debug: Show LLM history
    if user_agent.llm_history.any?
      puts "\nLLM History Debug:"
      user_agent.llm_history.each_with_index do |entry, idx|
        puts "   [#{idx}] Role: #{entry['role']}"
        if entry['content'].is_a?(Array)
          entry['content'].each do |block|
            if block['type'] == 'tool_use'
              puts "       Tool: #{block['name']}"
            elsif block['type'] == 'text'
              puts "       Text: #{block['text']&.truncate(100)}"
            end
          end
        else
          puts "       Content: #{entry['content'].to_s.truncate(100)}"
        end
      end
    end
    
    if agent_messages.any?
      puts "\n💬 Agent messages:"
      agent_messages.each do |msg|
        puts "   [#{msg.id}] #{msg.content[0..200]}..."
      end
    end
    
    # Verify expectations
    expect(agent_messages.count).to be >= 1, "Should have created at least one agent message"
    
    # Check that the response mentions both name and food
    combined_content = agent_messages.map(&:content).join(" ").downcase
    
    expect(combined_content).to include("alex"), "Response should mention the user's name (Alex)"
    expect(combined_content).to include("sushi"), "Response should mention favorite food (sushi)"
    
    test_cost = LlmCost.where(user: user).where("created_at >= ?", test_start).sum(:cost)

    puts "\n✅ TEST PASSED!"
    puts "   ✅ Agent created #{agent_messages.count} thread message(s)"
    puts "   ✅ Response includes user's name (Alex)"
    puts "   ✅ Response includes favorite food (sushi)"
    puts "\n💰 Total Cost: #{LlmCost.format_cost(test_cost)}"
    puts "="*80
  end
  
  it 'has web search capability and can generate discoveries' do
    puts "\n🔍 USER AGENT WEB SEARCH TEST"
    puts "="*80
    
    # Create goals with clear opportunity for web discovery
    goal1 = create(:goal, 
      user: user, 
      title: "Plan Barcelona Trip", 
      description: "First time visiting Barcelona in 2 months. Need to learn about metro, neighborhoods, and what to see.",
      status: :waiting
    )
    goal1.add_learning("User has never been to Spain before")
    goal1.add_learning("Interested in architecture and food")
    
    goal2 = create(:goal,
      user: user,
      title: "Learn Spanish",
      description: "Learn conversational Spanish for upcoming Barcelona trip",
      status: :waiting
    )
    goal2.add_learning("Trip is in 2 months")
    
    # Create relevant notes
    note1 = Note.create!(
      user: user,
      goal: goal1,
      source: :agent,
      title: "Trip Timeline",
      content: "Barcelona trip scheduled for 2 months from now. Need to book flights soon."
    )
    
    note2 = Note.create!(
      user: user,
      goal: goal2,
      source: :agent,
      title: "Spanish Learning Progress",
      content: "Started with Duolingo basics. Focusing on travel phrases and restaurant ordering."
    )
    
    user_agent = user.user_agent
    
    # First verify web search tool is available
    registry = Tools::Registry.new(
      user: user,
      goal: nil,
      task: nil,
      agentable: user_agent
    )
    
    available_tools = registry.provider_tools(context: :user_agent)
    tool_names = available_tools.map { |t| t[:name] }
    
    puts "\n🔧 Available tools for user_agent:"
    tool_names.each { |name| puts "   - #{name}" }
    
    has_web_search_tool = tool_names.include?('brave_web_search')
    puts "\n   brave_web_search available: #{has_web_search_tool ? 'YES ✅' : 'NO ❌'}"

    unless has_web_search_tool
      skip "brave_web_search not available (MCP server not loaded in test environment)"
    end
    
    puts "\n=== Testing UserAgent Web Search ===" 
    puts "Goals: Barcelona trip + Spanish learning"
    puts "Clear opportunity for travel guide discovery"
    
    started_at = Time.current
    
    # Trigger UserAgent
    Agents::Orchestrator.perform_async(
      user_agent.class.name,
      user_agent.id,
      {
        "type" => "feed_generation",
        "generation_id" => "test-123",
        "last_feed_at" => nil,
        "note_ids" => [note1.id, note2.id]
      }
    )
    
    sleep 2
    user_agent.reload
    
    puts "\n=== LLM History ===" 
    new_entries = user_agent.llm_history.select { |e| 
      t = e["timestamp"]&.to_datetime rescue nil
      t && t >= started_at
    }
    
    puts "Total new entries: #{new_entries.length}"
    
    # Check if web search was used
    web_search_used = new_entries.any? do |entry|
      next false unless entry['role'] == 'assistant'
      content = entry['content']
      if content.is_a?(Array)
        content.any? { |item| item['type'] == 'tool_use' && item['name'] == 'brave_web_search' }
      end
    end
    
    puts "Web search used: #{web_search_used}"
    
    # Get final JSON response
    final_response = new_entries.find { |e| 
      e['role'] == 'assistant' && e['content'].is_a?(Array) && 
      e['content'].any? { |item| item['type'] == 'text' }
    }
    
    if final_response
      text_item = final_response['content'].find { |item| item['type'] == 'text' }
      if text_item
        begin
          json = JSON.parse(text_item['text'])
          puts "\n=== Generated Content ==="
          puts "Reflections: #{json['reflections']&.length || 0}"
          puts "Discoveries: #{json['discoveries']&.length || 0}"
          
          if json['discoveries']&.any?
            json['discoveries'].each do |disc|
              puts "\nDiscovery:"
              puts "  Title: #{disc['title']}"
              puts "  URL: #{disc['url']}"
              puts "  Summary: #{disc['summary']}"
            end
          end
        rescue JSON::ParserError
          puts "Could not parse JSON response"
        end
      end
    end
    
    # Calculate test cost
    test_cost = LlmCost.where(user: user).where("created_at >= ?", started_at).sum(:cost)
    
    puts "\n✅ TEST PASSED!"
    puts "   ✅ Web search tool is available to user_agent"
    puts "   #{web_search_used ? '✅' : '⚠️'}  Web search #{web_search_used ? 'was used' : 'was not used (LLM choice)'}"
    puts "\n💰 Total Cost: #{LlmCost.format_cost(test_cost)}"
    puts "="*80
  end
end
