# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it 'has one user_agent' do
      expect(User.reflect_on_association(:user_agent).macro).to eq(:has_one)
    end
    
    it 'has many goals' do
      expect(User.reflect_on_association(:goals).macro).to eq(:has_many)
    end
    
    it 'has many notes' do
      expect(User.reflect_on_association(:notes).macro).to eq(:has_many)
    end
    
    it 'has many agent_tasks' do
      expect(User.reflect_on_association(:agent_tasks).macro).to eq(:has_many)
    end
  end
  
  describe 'user_agent creation' do
    it 'automatically creates user_agent when user is created' do
      user = User.create!(email: 'test@example.com')

      expect(user.user_agent).to be_present
      expect(user.user_agent).to be_persisted
      expect(user.user_agent.user).to eq(user)
    end
    
    it 'does not fail user creation if user_agent creation fails' do
      # Simulate UserAgent creation failure
      allow(UserAgent).to receive(:create!).and_raise(StandardError.new('Test error'))

      user = User.create!(email: 'test@example.com')

      expect(user).to be_persisted
    end
  end
  
  describe 'validations' do
    it 'requires email' do
      user = User.new
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end
    
    it 'requires unique email' do
      User.create!(email: 'test@example.com')
      duplicate = User.new(email: 'test@example.com')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include('has already been taken')
    end
    
    it 'downcases email before validation' do
      user = User.create!(email: 'TEST@EXAMPLE.COM')

      expect(user.email).to eq('test@example.com')
    end
  end
end
