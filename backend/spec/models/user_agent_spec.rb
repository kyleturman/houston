# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserAgent, type: :model do
  let(:user) { create(:user) }
  
  describe 'validations' do
    it 'requires user_id' do
      user_agent = UserAgent.new
      expect(user_agent).not_to be_valid
      expect(user_agent.errors[:user_id]).to include("can't be blank")
    end
    
    it 'enforces unique user_id' do
      # User already has a user_agent from after_create callback
      # Try to create another one
      duplicate = UserAgent.new(user: user)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to include('has already been taken')
    end
    
    it 'is valid with user' do
      new_user = create(:user)
      # Destroy the auto-created user_agent to test validation
      new_user.user_agent.destroy
      
      user_agent = UserAgent.new(user: new_user)
      expect(user_agent).to be_valid
    end
  end
  
  describe 'associations' do
    it 'belongs to user' do
      expect(UserAgent.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
    
    it 'has many thread_messages as agentable' do
      expect(UserAgent.reflect_on_association(:thread_messages).macro).to eq(:has_many)
      expect(UserAgent.reflect_on_association(:thread_messages).options[:as]).to eq(:agentable)
    end
  end
  
  describe 'agentable concern' do
    let(:user_agent) { user.user_agent }
    
    it 'includes agentable functionality' do
      expect(user_agent).to respond_to(:get_llm_history)
      expect(user_agent).to respond_to(:add_to_llm_history)
      expect(user_agent).to respond_to(:agent_active?)
      expect(user_agent).to respond_to(:claim_execution_lock!)
    end
    
    it 'identifies as user_agent type' do
      expect(user_agent.agent_type).to eq('user_agent')
      expect(user_agent.user_agent?).to be true
      expect(user_agent.goal?).to be false
      expect(user_agent.task?).to be false
    end
    
    it 'is always active' do
      expect(user_agent.agent_active?).to be true
    end
    
    it 'can manage LLM history' do
      user_agent.add_to_llm_history({ role: 'user', content: 'Test message' })
      user_agent.save!
      user_agent.reload
      history = user_agent.get_llm_history

      expect(history).to be_an(Array)
      expect(history.last['role']).to eq('user')
      expect(history.last['content']).to eq('Test message')
    end
  end
  
  describe 'learning management' do
    let(:user_agent) { user.user_agent }
    
    it 'starts with empty learnings' do
      user_agent.reload
      expect(user_agent.learnings).to eq([])
    end
    
    it 'can add learnings' do
      user_agent.add_learning('User prefers morning work sessions')
      user_agent.reload
      
      expect(user_agent.learnings.length).to eq(1)
      expect(user_agent.learnings.first['content']).to eq('User prefers morning work sessions')
      expect(user_agent.learnings.first['created_at']).to be_present
    end
    
    it 'can add multiple learnings' do
      user_agent.add_learning('First learning')
      user_agent.add_learning('Second learning')
      user_agent.add_learning('Third learning')
      user_agent.reload
      
      expect(user_agent.learnings.length).to eq(3)
    end
    
    it 'returns relevant learnings in reverse order' do
      5.times { |i| user_agent.add_learning("Learning #{i + 1}") }
      user_agent.reload
      
      relevant = user_agent.relevant_learnings(limit: 3)
      
      expect(relevant.length).to eq(3)
      expect(relevant.first['content']).to eq('Learning 5')
      expect(relevant.last['content']).to eq('Learning 3')
    end
    
    it 'respects limit parameter' do
      10.times { |i| user_agent.add_learning("Learning #{i + 1}") }
      user_agent.reload
      
      expect(user_agent.relevant_learnings(limit: 5).length).to eq(5)
      expect(user_agent.relevant_learnings(limit: 10).length).to eq(10)
    end
  end
  
  describe '#start_orchestrator!' do
    let(:user_agent) { user.user_agent }
    
    it 'can start orchestrator' do
      expect(user_agent).to respond_to(:start_orchestrator!)
    end
    
    it 'returns job_id when started' do
      allow(Agents::Orchestrator).to receive(:perform_in).and_return('job_123')
      
      result = user_agent.start_orchestrator!
      
      expect(result).to eq('job_123')
    end
  end
end
