# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ThreadMessage, type: :model do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }
  let!(:task) { AgentTask.create!(title: 'Test Task', priority: 'normal', status: 'active', goal: goal, user: user) }
  
  describe 'validations' do
    it 'requires user' do
      message = ThreadMessage.new(agentable: goal, source: 'user', content: 'Test message')
      expect(message).not_to be_valid
      expect(message.errors[:user]).to include('must exist')
    end
    
    it 'requires agentable' do
      message = ThreadMessage.new(user: user, source: 'user', content: 'Test message')
      expect(message).not_to be_valid
      expect(message.errors[:agentable]).to include('must exist')
    end
    
    it 'requires source' do
      message = ThreadMessage.new(user: user, agentable: goal, content: 'Test message', source: nil)
      expect(message).not_to be_valid
      expect(message.errors[:source]).to include("can't be blank")
    end
    
    it 'requires content or metadata' do
      message = ThreadMessage.new(user: user, agentable: goal, source: 'user')
      expect(message).not_to be_valid
      expect(message.errors[:base]).to include('Either content or metadata must be present')
    end
    
    
    it 'accepts valid sources' do
      %w[user agent error].each do |source|
        message = ThreadMessage.new(user: user, agentable: goal, source: source, content: 'Test')
        expect(message).to be_valid, "Expected source #{source} to be valid"
      end
    end
  end
  
  describe 'associations' do
    it 'belongs to user' do
      expect(ThreadMessage.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
    
    it 'belongs to agentable polymorphically' do
      association = ThreadMessage.reflect_on_association(:agentable)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:polymorphic]).to be true
    end
  end
  
  describe 'polymorphic agentable association' do
    it 'works with Goal' do
      message = create(:thread_message, :for_goal, user: user, agentable: goal)
      expect(message.agentable).to eq(goal)
      expect(message.agentable_type).to eq('Goal')
    end
    
    it 'works with AgentTask' do
      message = create(:thread_message, :for_task, user: user, agentable: task)
      expect(message.agentable).to eq(task)
      expect(message.agentable_type).to eq('AgentTask')
    end
  end
  
  describe 'message threading' do
    let!(:goal_message1) { create(:thread_message, user: user, agentable: goal, created_at: 1.hour.ago) }
    let!(:goal_message2) { create(:thread_message, user: user, agentable: goal, created_at: 30.minutes.ago) }
    let!(:task_message) { create(:thread_message, user: user, agentable: task, created_at: 15.minutes.ago) }
    
    it 'groups messages by agentable' do
      goal_messages = ThreadMessage.where(agentable: goal)
      expect(goal_messages).to include(goal_message1, goal_message2)
      expect(goal_messages).not_to include(task_message)
      
      task_messages = ThreadMessage.where(agentable: task)
      expect(task_messages).to include(task_message)
      expect(task_messages).not_to include(goal_message1, goal_message2)
    end
    
    it 'orders messages chronologically' do
      messages = ThreadMessage.where(agentable: goal).order(:created_at)
      expect(messages.to_a).to eq([goal_message1, goal_message2])
    end
  end
  
  describe 'source types' do
    it 'creates user messages' do
      message = create(:thread_message, :user_message, user: user, agentable: goal)
      expect(message.source).to eq('user')
      expect(message.content).to include('User message')
    end
    
    it 'creates agent messages' do
      message = create(:thread_message, :agent_message, user: user, agentable: goal)
      expect(message.source).to eq('agent')
      expect(message.content).to include('Agent response')
    end
    
    it 'creates system messages' do
      message = create(:thread_message, :system_message, user: user, agentable: goal)
      expect(message.source).to eq('error')
      expect(message.content).to include('System notification')
    end
  end
  
  describe 'metadata handling' do
    it 'stores tool activity metadata' do
      message = create(:thread_message, :with_tool_activity, user: user, agentable: goal)

      expect(message.metadata).to be_a(Hash)
      expect(message.metadata['tool_activity']).to be_present
      expect(message.metadata['tool_activity']['name']).to eq('create_note')
      expect(message.metadata['tool_activity']['status']).to eq('success')
      expect(message.metadata['tool_activity']['data']).to be_present
      expect(message.metadata['tool_activity']['data']['note_id']).to be_present
    end
    
    it 'defaults metadata to empty hash' do
      message = create(:thread_message, user: user, agentable: goal)
      expect(message.metadata).to eq({})
    end
  end
  
  describe 'scopes' do
    let!(:user_message) { create(:thread_message, :user_message, user: user, agentable: goal) }
    let!(:agent_message) { create(:thread_message, :agent_message, user: user, agentable: goal) }
    let!(:system_message) { create(:thread_message, :system_message, user: user, agentable: goal) }
    
    it 'filters by source' do
      user_messages = ThreadMessage.where(source: 'user')
      expect(user_messages).to include(user_message)
      expect(user_messages).not_to include(agent_message, system_message)

      agent_messages = ThreadMessage.where(source: 'agent')
      expect(agent_messages).to include(agent_message)
      expect(agent_messages).not_to include(user_message, system_message)

      error_messages = ThreadMessage.where(source: 'error')
      expect(error_messages).to include(system_message)
      expect(error_messages).not_to include(user_message, agent_message)
    end
  end
end
