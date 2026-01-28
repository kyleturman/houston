# frozen_string_literal: true

require 'rails_helper'

# Dedicated test for diagnosing agent execution issues
# Run with: bundle exec rspec spec/integration/agent_execution_debug_spec.rb
RSpec.describe 'Agent Execution Debugging', type: :integration do
  include_context 'authenticated user'
  
  let(:test_user) { user }
  
  describe 'CoreLoop execution' do
    it 'triggers orchestrator without hanging (mocked)', :debug_agent do
      puts "\n🔍 Testing orchestrator trigger with mocked execution..."
      
      goal = Goal.create_with_agent!(
        user: user,
        title: "Debug Test Goal",
        description: "Testing CoreLoop execution"
      )
      
      # Trigger orchestrator (should return immediately due to mock)
      Agents::Orchestrator.perform_async(
        goal.class.name,
        goal.id,
        { "triggered_by" => "test" }
      )
      
      puts "✅ Orchestrator triggered and returned (mock executed)"
    end
    
    it 'creates AgentTask without hanging (mocked)', :debug_agent do
      puts "\n🔍 Testing AgentTask creation with mocked orchestrator..."
      
      goal = Goal.create_with_agent!(
        user: user,
        title: "Task Test Goal",
        description: "Testing task creation"
      )
      
      # AgentTask.create triggers after_create :start_orchestrator! (mocked)
      task = AgentTask.create!(
        goal: goal,
        user: user,
        title: "Test Task",
        instructions: "This should trigger orchestrator",
        status: 'active'
      )
      
      expect(task).to be_persisted
      puts "✅ AgentTask created and orchestrator triggered (mock executed)"
    end
  end
  
  describe 'Service.agent_call behavior' do
    it 'properly returns mocked results', :debug_agent do
      puts "\n🔍 Testing Service.agent_call mock..."
      
      goal = Goal.create_with_agent!(
        user: user,
        title: "Service Test Goal",
        description: "Testing service mock"
      )
      
      # Directly test Service.agent_call
      result = Llms::Service.agent_call(
        agentable: goal,
        user: user,
        system: "Test system prompt",
        messages: [{ role: 'user', content: 'test' }],
        tools: []
      )
      
      expect(result).to be_a(Hash)
      expect(result).to have_key(:response)
      expect(result).to have_key(:tool_calls)
      expect(result).to have_key(:policy)
      
      puts "✅ Service.agent_call mock working correctly"
      puts "   Response type: #{result[:response].class}"
      puts "   Tool calls: #{result[:tool_calls].count}"
    end
  end
end
