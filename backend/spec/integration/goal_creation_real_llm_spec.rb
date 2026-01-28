# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Goal Creation Chat with Real LLM' do
  let(:user) { create(:user) }

  describe 'Real LLM conversation flow', :real_llm do
    before do
      # Verify required ENV vars are set
      unless ENV['LLM_AGENTS_MODEL'] && !ENV['LLM_AGENTS_MODEL'].empty?
        skip 'Goal creation test requires LLM_AGENTS_MODEL to be set'
      end
    end
    
    it 'completes a full conversation and extracts goal data' do
      skip 'Set USE_REAL_LLM=true to run this test' unless ENV['USE_REAL_LLM'] == 'true'

      puts "\n" + "="*80
      puts "🤖 TESTING GOAL CREATION CHAT WITH REAL LLM"
      puts "="*80
      
      test_start = Time.current
      conversation_history = []
      goal_data = nil
      turn_count = 0
      max_turns = 10
      
      # Start with a comprehensive initial message
      user_message = "I want to get fit and healthy. I work long hours as a software engineer and have two young kids (ages 3 and 5), so time is very limited. I can maybe do 30 minutes 3 times a week."
      
      loop do
        turn_count += 1
        break if turn_count > max_turns
        
        puts "\n" + "-"*80
        puts "📤 TURN #{turn_count} - User Message:"
        puts "   #{user_message[0..100]}#{user_message.length > 100 ? '...' : ''}"
        
        # Build messages for LLM
        messages = []
        conversation_history.each do |msg|
          messages << {
            role: msg[:role],
            content: [{ type: 'text', text: msg[:content] }]
          }
        end
        messages << {
          role: 'user',
          content: [{ type: 'text', text: user_message }]
        }
        
        # Call LLM service directly
        result = Llms::Service.call(
          system: Llms::Prompts::Goals.creation_chat_system_prompt,
          messages: messages,
          tools: [Llms::Prompts::Goals.creation_tool_definition],
          user: user
        )
        
        content_blocks = result[:content]
        tool_calls = result[:tool_calls] || []
        ready_to_create = tool_calls.any? { |tc| tc[:name] == 'finalize_goal_creation' }
        
        # Extract text from content blocks
        assistant_reply = content_blocks.map { |block| block[:text] }.join("\n")
        
        puts "📥 TURN #{turn_count} - Assistant Reply:"
        puts "   #{assistant_reply[0..100]}#{assistant_reply.length > 100 ? '...' : ''}"
        puts "   Ready to create: #{ready_to_create}"
        
        # Validate response structure
        expect(assistant_reply).to be_a(String)
        # Note: assistant_reply can be empty when tool is called
        expect(assistant_reply.length).to be >= 0
        
        # Add to conversation history
        conversation_history << { role: 'user', content: user_message }
        conversation_history << { role: 'assistant', content: assistant_reply }
        
        # Check if ready to create
        if ready_to_create
          tool_call = tool_calls.find { |tc| tc[:name] == 'finalize_goal_creation' }
          # Canonical tool call format: { name:, parameters:, call_id: }
          goal_data = tool_call[:parameters] if tool_call
          puts "\n✅ GOAL CREATION READY AFTER #{turn_count} TURNS!"
          break
        end
        
        # Simulate realistic user responses
        user_message = case turn_count
                      when 1
                        "I prefer home workouts since I can't get to a gym easily. Maybe bodyweight exercises or yoga. I've tried workout apps before but lost motivation after a few weeks."
                      when 2
                        "I think accountability would help - maybe tracking progress or having structured workouts. My main goal is to have more energy and feel healthier overall."
                      when 3
                        "Yes, that sounds perfect. Let's create the goal."
                      else
                        "That covers everything. Let's proceed with creating the goal."
                      end
      end
      
      # Verify goal data was extracted
      expect(goal_data).to be_present, 
             "Goal data should be present after conversation. Last reply: #{conversation_history.last}"
      
      puts "\n" + "="*80
      puts "📋 EXTRACTED GOAL DATA:"
      puts "="*80
      puts "Title: #{goal_data['title']}"
      puts "\nDescription:"
      puts "  #{goal_data['description']}"
      puts "\nAgent Instructions:"
      puts "  #{goal_data['agent_instructions'][0..150]}..."
      puts "\nLearnings (#{goal_data['learnings'].length} items):"
      goal_data['learnings'].each_with_index do |learning, i|
        puts "  #{i+1}. #{learning}"
      end
      puts "="*80
      
      # Validate goal data structure
      expect(goal_data['title']).to be_present
      expect(goal_data['description']).to be_present
      expect(goal_data['agent_instructions']).to be_present
      expect(goal_data['learnings']).to be_an(Array)
      
      # Validate content quality
      expect(goal_data['title'].length).to be_between(3, 100), 
             "Title should be concise: #{goal_data['title']}"
      expect(goal_data['description'].length).to be_between(20, 500), 
             "Description should be detailed but concise"
      expect(goal_data['agent_instructions'].length).to be > 50, 
             "Agent instructions should be detailed"
      expect(goal_data['learnings'].length).to be_between(1, 10), 
             "Should have reasonable number of learnings"
      
      # Verify learnings captured key context
      learnings_text = goal_data['learnings'].join(' ').downcase
      expect(learnings_text).to match(/kids|children|family|time|limited|busy/), 
             "Should capture time constraints"
      
      # Verify agent instructions are contextual
      instructions = goal_data['agent_instructions'].downcase
      expect(instructions).to match(/fit|health|exercise|workout/), 
             "Instructions should relate to fitness goal"
      
      # Test creating actual goal from extracted data
      # Stub orchestrator to avoid cascading real LLM calls during goal creation
      puts "\n🎯 CREATING ACTUAL GOAL FROM EXTRACTED DATA..."

      initial_goal_count = Goal.count
      allow_any_instance_of(Goal).to receive(:start_orchestrator!).and_return(nil)

      goal = Goal.create_with_agent!(
        user: user,
        title: goal_data['title'],
        description: goal_data['description'],
        agent_instructions: goal_data['agent_instructions'],
        learnings: goal_data['learnings']
      )

      expect(Goal.count).to eq(initial_goal_count + 1), "Goal should be created"
      expect(goal.title).to eq(goal_data['title'])
      expect(goal.description).to eq(goal_data['description'])
      expect(goal.agent_instructions).to be_present, "Goal should have agent instructions"
      expect(goal.status).to eq('working'), "Goal should be in working status"

      puts "✅ Goal created successfully!"
      puts "   ID: #{goal.id}"
      puts "   Title: #{goal.title}"
      puts "   Status: #{goal.status}"
      
      # Calculate test cost
      test_cost = LlmCost.where(user: user).where("created_at >= ?", test_start).sum(:cost)
      
      puts "\n" + "="*80
      puts "✨ GOAL CREATION CHAT TEST PASSED!"
      puts "   Turns: #{turn_count}"
      puts "   Learnings extracted: #{goal_data['learnings'].length}"
      puts "   Goal created: #{goal.id}"
      puts "\n💰 Total Cost: #{LlmCost.format_cost(test_cost)}"
      puts "="*80 + "\n"
      
      # Cleanup
      goal.destroy
    end

    it 'handles brief vs detailed initial messages' do
      skip 'Set USE_REAL_LLM=true to run this test' unless ENV['USE_REAL_LLM'] == 'true'

      puts "\n🧪 Testing different message styles..."
      test_start = Time.current
      
      test_cases = [
        {
          name: 'Brief message',
          message: 'Learn piano'
        },
        {
          name: 'Detailed message',
          message: "I want to learn piano. I'm a complete beginner with no music experience. I have about 30 minutes daily to practice and would like to play simple songs within 6 months."
        }
      ]
      
      test_cases.each do |test_case|
        puts "\n  Testing: #{test_case[:name]}"
        puts "  Message: #{test_case[:message][0..60]}..."
        
        result = Llms::Service.call(
          system: Llms::Prompts::Goals.creation_chat_system_prompt,
          messages: [{ role: 'user', content: [{ type: 'text', text: test_case[:message] }] }],
          tools: [Llms::Prompts::Goals.creation_tool_definition],
          user: user
        )
        
        content_blocks = result[:content]
        tool_calls = result[:tool_calls] || []
        
        # Extract text from content blocks
        reply = content_blocks.map { |block| block[:text] }.join("\n")
        
        expect(reply).to be_present
        expect(tool_calls).to be_empty, "Should not be ready after first message - need more info"
        
        # Check if LLM asked a question (should engage with user, not create immediately)
        expect(reply).to include('?'), 
               "Response should ask clarifying questions. Got: #{reply[0..200]}"
        
        puts "  ✓ Assistant asked follow-up questions"
        puts "    Reply: #{reply[0..80]}..."
      end
      
      # Calculate test cost
      test_cost = LlmCost.where(user: user).where("created_at >= ?", test_start).sum(:cost)
      puts "\n💰 Total Cost: #{LlmCost.format_cost(test_cost)}"
    end

    it 'completes efficiently with comprehensive information' do
      skip 'Set USE_REAL_LLM=true to run this test' unless ENV['USE_REAL_LLM'] == 'true'

      puts "\n⏱️  Testing conversation efficiency..."
      test_start = Time.current
      
      conversation_history = []
      turn_count = 0
      goal_data = nil
      
      # Provide very comprehensive information upfront
      messages = [
        "I want to learn web development to switch careers from teaching. I'm 32 years old with a background in high school math. I have 2-3 hours per day to study after work. I prefer hands-on projects over theory and learn best by building real things. I've tried online courses before (Udemy, Coursera) but struggled with staying motivated without structure. My goal is to be job-ready as a junior developer in 6-8 months. I'm interested in full-stack development, particularly React and Node.js.",
        "I want to build a portfolio with 3-5 real projects that I can show to employers. I'm comfortable with basic HTML/CSS but need to learn JavaScript deeply, plus backend development and databases.",
        "Yes, that covers everything. Let's create the goal."
      ]
      
      messages.each_with_index do |message, index|
        turn_count = index + 1
        
        # Build LLM messages
        llm_messages = []
        conversation_history.each do |msg|
          llm_messages << {
            role: msg[:role],
            content: [{ type: 'text', text: msg[:content] }]
          }
        end
        llm_messages << {
          role: 'user',
          content: [{ type: 'text', text: message }]
        }
        
        result = Llms::Service.call(
          system: Llms::Prompts::Goals.creation_chat_system_prompt,
          messages: llm_messages,
          tools: [Llms::Prompts::Goals.creation_tool_definition],
          user: user
        )
        
        content_blocks = result[:content]
        tool_calls = result[:tool_calls] || []
        
        # Extract text from content blocks
        reply = content_blocks.map { |block| block[:text] }.join("\n")
        
        conversation_history << { role: 'user', content: message }
        conversation_history << { role: 'assistant', content: reply }
        
        if tool_calls.any? { |tc| tc[:name] == 'finalize_goal_creation' }
          tool_call = tool_calls.find { |tc| tc[:name] == 'finalize_goal_creation' }
          goal_data = tool_call[:parameters]
          puts "  ✓ Goal ready after #{turn_count} turns (efficient!)"
          
          # Verify comprehensive learnings were extracted
          expect(goal_data['learnings'].length).to be >= 4, 
                 "Should extract multiple learnings from detailed input"
          
          learnings_text = goal_data['learnings'].join(' ').downcase
          expect(learnings_text).to match(/teaching|career|switch/), 
                 "Should capture career context"
          expect(learnings_text).to match(/hands-on|project|building/), 
                 "Should capture learning preference"
          expect(learnings_text).to match(/react|node|javascript|full-stack/), 
                 "Should capture technology preferences"
          
          break
        end
      end
      
      expect(turn_count).to be <= 5, 
             "Should complete within 5 turns when user provides comprehensive information"
      expect(goal_data).to be_present, "Should have extracted goal data"
      
      # Calculate test cost
      test_cost = LlmCost.where(user: user).where("created_at >= ?", test_start).sum(:cost)
      
      puts "  ✓ Conversation completed efficiently in #{turn_count} turns"
      puts "  ✓ Extracted #{goal_data['learnings'].length} learnings"
      puts "\n💰 Total Cost: #{LlmCost.format_cost(test_cost)}"
    end
  end
end
