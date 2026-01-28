# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::Orchestrator, type: :service do
  describe 'smoke test - orchestrator can start without errors', :core do
    let(:user) { create(:user) }
    let(:goal) { create(:goal, user: user, title: "Test Goal", status: :waiting) }
    
    it 'can build system prompt without errors' do
      # Test that all prompt building works (catches missing methods, syntax errors)
      orchestrator = described_class.new
      orchestrator.instance_variable_set(:@agentable, goal)
      orchestrator.instance_variable_set(:@user, user)
      orchestrator.instance_variable_set(:@context, {})
      
      # This should not raise any errors (like NoMethodError for build_learnings_xml)
      expect {
        orchestrator.send(:build_system_prompt)
      }.not_to raise_error
    end
    
    it 'can build context message without errors' do
      # Test that context building works
      orchestrator = described_class.new
      orchestrator.instance_variable_set(:@agentable, goal)
      orchestrator.instance_variable_set(:@user, user)
      orchestrator.instance_variable_set(:@context, { 'type' => 'feed_generation' })

      expect {
        orchestrator.send(:build_context_message)
      }.not_to raise_error
    end
  end
end
