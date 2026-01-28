# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::HistoryValidator do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }

  describe '#validate_and_repair!' do
    context 'with empty history' do
      it 'returns valid result' do
        goal.update_column(:llm_history, [])

        result = described_class.new(goal).validate_and_repair!

        expect(result.valid).to be true
        expect(result.repairs).to be_empty
        expect(result.repaired?).to be false
      end
    end

    context 'with valid history' do
      it 'returns valid result when tool_use has matching tool_result' do
        history = [
          {
            'role' => 'user',
            'content' => 'Hello'
          },
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'text', 'text' => 'Let me search for that.' },
              { 'type' => 'tool_use', 'id' => 'toolu_123', 'name' => 'search_notes', 'input' => { 'query' => 'test' } }
            ]
          },
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'toolu_123', 'content' => 'Found 3 notes' }
            ]
          }
        ]
        goal.update_column(:llm_history, history)

        result = described_class.new(goal).validate_and_repair!

        expect(result.valid).to be true
        expect(result.repairs).to be_empty
        expect(result.repaired?).to be false
      end
    end

    context 'with orphaned tool_use (missing tool_result)' do
      it 'repairs by adding synthetic tool_result' do
        history = [
          {
            'role' => 'user',
            'content' => 'Hello'
          },
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'text', 'text' => 'Let me search for that.' },
              { 'type' => 'tool_use', 'id' => 'toolu_orphaned', 'name' => 'search_notes', 'input' => { 'query' => 'test' } }
            ]
          }
          # Missing tool_result - simulates crash during tool execution
        ]
        goal.update_column(:llm_history, history)

        result = described_class.new(goal).validate_and_repair!

        expect(result.valid).to be true
        expect(result.repaired?).to be true
        expect(result.repairs).to include(/Added missing tool_result for search_notes/)

        # Verify the repair was persisted
        repaired_history = goal.reload.llm_history
        expect(repaired_history.length).to eq(3)

        tool_result_message = repaired_history.last
        expect(tool_result_message['role']).to eq('user')
        expect(tool_result_message['content']).to be_an(Array)

        tool_result = tool_result_message['content'].first
        expect(tool_result['type']).to eq('tool_result')
        expect(tool_result['tool_use_id']).to eq('toolu_orphaned')
        expect(tool_result['is_error']).to be true
        expect(tool_result['content']).to include('interrupted')
      end

      it 'repairs multiple orphaned tools in same message' do
        history = [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'tool_use', 'id' => 'toolu_1', 'name' => 'search_notes', 'input' => {} },
              { 'type' => 'tool_use', 'id' => 'toolu_2', 'name' => 'create_note', 'input' => {} }
            ]
          }
        ]
        goal.update_column(:llm_history, history)

        result = described_class.new(goal).validate_and_repair!

        expect(result.repaired?).to be true
        expect(result.repairs.length).to eq(2)

        repaired_history = goal.reload.llm_history
        tool_results = repaired_history.last['content']
        expect(tool_results.length).to eq(2)
        expect(tool_results.map { |tr| tr['tool_use_id'] }).to contain_exactly('toolu_1', 'toolu_2')
      end

      it 'adds synthetic result to existing user message with other content' do
        history = [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'tool_use', 'id' => 'toolu_1', 'name' => 'search_notes', 'input' => {} },
              { 'type' => 'tool_use', 'id' => 'toolu_2', 'name' => 'create_note', 'input' => {} }
            ]
          },
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'toolu_1', 'content' => 'Found results' }
              # Missing toolu_2 result
            ]
          }
        ]
        goal.update_column(:llm_history, history)

        result = described_class.new(goal).validate_and_repair!

        expect(result.repaired?).to be true
        expect(result.repairs.length).to eq(1)
        expect(result.repairs.first).to include('create_note')

        # Verify repair was added to existing message
        repaired_history = goal.reload.llm_history
        expect(repaired_history.length).to eq(2) # No new message added

        tool_results = repaired_history.last['content']
        expect(tool_results.length).to eq(2)
        expect(tool_results.map { |tr| tr['tool_use_id'] }).to contain_exactly('toolu_1', 'toolu_2')
      end
    end

    context 'with nil content' do
      it 'reports error for nil content' do
        history = [
          { 'role' => 'user', 'content' => nil }
        ]
        goal.update_column(:llm_history, history)

        result = described_class.new(goal).validate_and_repair!

        expect(result.errors).to include(/nil content/)
      end
    end

    context 'with invalid role' do
      it 'reports error for invalid role' do
        history = [
          { 'role' => 'system', 'content' => 'Hello' }
        ]
        goal.update_column(:llm_history, history)

        result = described_class.new(goal).validate_and_repair!

        expect(result.errors).to include(/invalid role/)
      end
    end
  end

  describe '#valid?' do
    it 'returns true for valid history' do
      history = [
        { 'role' => 'user', 'content' => 'Hello' },
        { 'role' => 'assistant', 'content' => 'Hi there!' }
      ]
      goal.update_column(:llm_history, history)

      expect(described_class.new(goal).valid?).to be true
    end

    it 'returns false for orphaned tool_use' do
      history = [
        {
          'role' => 'assistant',
          'content' => [
            { 'type' => 'tool_use', 'id' => 'toolu_orphaned', 'name' => 'search', 'input' => {} }
          ]
        }
      ]
      goal.update_column(:llm_history, history)

      expect(described_class.new(goal).valid?).to be false
    end
  end
end
