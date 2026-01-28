# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llms::Adapters, type: :service do
  let(:user) { FactoryBot.create(:user) }
  let(:goal) { FactoryBot.create(:goal, user: user) }
  
  describe '.for with cost tracking', :skip_adapter_mock do
    it 'creates adapter for agents with tracking setup' do
      adapter = Llms::Adapters.for(:agents, user: user, agentable: goal, context: 'test')

      expect(adapter).to be_a(Llms::Adapters::Base)
      expect(adapter.model_key).to eq('sonnet-4.5')
    end

    it 'creates adapter for tasks with tracking setup' do
      adapter = Llms::Adapters.for(:tasks, user: user, agentable: goal, context: 'test')

      expect(adapter).to be_a(Llms::Adapters::Base)
      expect(adapter.model_key).to eq('haiku-4.5')
    end
  end
  
  describe 'cost tracking setup' do
    it 'sets up tracking when provided user' do
      adapter = Llms::Adapters.get(:anthropic, 'sonnet-4.5', user: user, agentable: goal, context: 'test')
      
      # Verify the tracking was setup (accessing instance variables for test)
      expect(adapter.instance_variable_get(:@tracking_user)).to eq(user)
      expect(adapter.instance_variable_get(:@tracking_agentable)).to eq(goal)
      expect(adapter.instance_variable_get(:@tracking_context)).to eq('test')
    end
    
    it 'adapter without user has no tracking user' do
      adapter = Llms::Adapters.get(:anthropic, 'sonnet-4.5')
      
      expect(adapter.instance_variable_get(:@tracking_user)).to be_nil
    end
  end
end
