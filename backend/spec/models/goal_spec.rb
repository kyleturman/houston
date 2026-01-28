# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Goal, type: :model do
  let(:user) { create(:user) }
  
  describe 'validations' do
    it 'requires title' do
      goal = Goal.new(user: user, description: 'Test description')
      expect(goal).not_to be_valid
      expect(goal.errors[:title]).to include("can't be blank")
    end
    
    it 'allows nil description' do
      goal = Goal.new(user: user, title: 'Test Goal')
      expect(goal).to be_valid
    end
    
    it 'requires user' do
      goal = Goal.new(title: 'Test Goal', description: 'Test description')
      expect(goal).not_to be_valid
      expect(goal.errors[:user]).to include('must exist')
    end
    
    it 'is valid with all required attributes' do
      goal = Goal.new(user: user, title: 'Test Goal', description: 'Test description')
      expect(goal).to be_valid
    end
  end
  
  describe 'associations' do
    it 'belongs to user' do
      expect(Goal.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
    
    it 'has many agent_tasks' do
      expect(Goal.reflect_on_association(:agent_tasks).macro).to eq(:has_many)
    end
    
    it 'has many thread_messages as agentable' do
      expect(Goal.reflect_on_association(:thread_messages).macro).to eq(:has_many)
      expect(Goal.reflect_on_association(:thread_messages).options[:as]).to eq(:agentable)
    end
    
    it 'has many notes through user' do
      # Notes are associated through user, not directly to goal
      goal = create(:goal, user: user)
      note = Note.create!(user: user, title: 'Test Note', content: 'Test content', source: 'user')
      
      expect(goal.user.notes).to include(note)
    end
  end
  
  describe 'status' do
    it 'starts as working when created with agent' do
      goal = Goal.create_with_agent!(user: user, title: 'Test Goal', description: 'Test description')
      expect(goal.status).to eq('working')
    end
    
    it 'can transition between states' do
      goal = create(:goal, user: user, status: 'waiting')
      
      goal.update!(status: 'working')
      expect(goal.status).to eq('working')
      
      goal.update!(status: 'archived')
      expect(goal.status).to eq('archived')
    end
    
    it 'has active? method for backward compatibility' do
      waiting_goal = create(:goal, user: user, status: 'waiting')
      working_goal = create(:goal, user: user, status: 'working')
      archived_goal = create(:goal, user: user, status: 'archived')
      
      expect(waiting_goal.active?).to be true
      expect(working_goal.active?).to be true
      expect(archived_goal.active?).to be false
    end
  end
  
  describe '.create_with_agent!' do
    it 'creates goal and starts agent' do
      goal = Goal.create_with_agent!(
        user: user,
        title: 'Test Goal',
        description: 'Test description'
      )
      
      expect(goal).to be_persisted
      expect(goal.status).to eq('working')
      expect(goal.user).to eq(user)
    end
  end
  
  describe 'agentable concern' do
    it 'includes agentable functionality' do
      goal = create(:goal, user: user)
      expect(goal).to respond_to(:get_llm_history)
      expect(goal).to respond_to(:add_to_llm_history)
      expect(goal).to respond_to(:agent_active?)
      expect(goal).to respond_to(:claim_execution_lock!)
    end
  end
end
