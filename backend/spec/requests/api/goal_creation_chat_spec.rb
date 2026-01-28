# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Goal Creation Chat', :service, :fast do
  describe 'Prompt generation' do
    it 'generates goal creation chat system prompt' do
      prompt = Llms::Prompts::Goals.creation_chat_system_prompt
      
      expect(prompt).to be_a(String)
      expect(prompt.length).to be > 100
      expect(prompt).to include('create goals')
      expect(prompt).to include('3-5 messages')
      expect(prompt).to include('finalize_goal_creation')
      expect(prompt).to include('Title')
      expect(prompt).to include('Description')
      expect(prompt).to include('Agent Instructions')
      expect(prompt).to include('Learnings')
    end
  end
  
  describe 'Tool definition' do
    it 'has correct structure for finalize_goal_creation tool' do
      tool = Llms::Prompts::Goals.creation_tool_definition
      
      expect(tool[:name]).to eq('finalize_goal_creation')
      expect(tool[:input_schema][:required]).to include('title')
      expect(tool[:input_schema][:required]).to include('description')
      expect(tool[:input_schema][:required]).to include('agent_instructions')
      expect(tool[:input_schema][:required]).to include('learnings')
    end
  end
end
