# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents::TaskSummarizer, type: :service do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }
  let(:task) { create(:agent_task, user: user, goal: goal, title: "Test Task") }

  describe '#summarize' do
    context 'with empty LLM history' do
      before do
        allow(task).to receive(:get_llm_history).and_return([])
      end

      it 'returns default summary' do
        summarizer = described_class.new(task)
        expect(summarizer.summarize).to eq("Task completed")
      end
    end

    context 'when agent ends with a text message (primary path)' do
      let(:llm_history) do
        [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'tool_use', 'id' => 'tool_1', 'name' => 'spotify_create_playlist' }
            ]
          },
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'tool_1', 'content' => '{"id": "abc123"}' }
            ]
          },
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'text', 'text' => "Created playlist 'Weekly Discoveries' (ID: abc123) with 15 upbeat tracks." }
            ]
          }
        ]
      end

      before do
        allow(task).to receive(:get_llm_history).and_return(llm_history)
      end

      it 'uses the agent final text as summary' do
        summarizer = described_class.new(task)
        expect(summarizer.summarize).to eq("Created playlist 'Weekly Discoveries' (ID: abc123) with 15 upbeat tracks.")
      end
    end

    context 'when agent ends with only tool calls (fallback path)' do
      let(:llm_history) do
        [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'tool_use', 'id' => 'tool_1', 'name' => 'create_playlist' }
            ]
          },
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'tool_1', 'content' => '{"id": "xyz789", "name": "My Playlist"}' }
            ]
          }
        ]
      end

      before do
        allow(task).to receive(:get_llm_history).and_return(llm_history)
      end

      it 'extracts from the last tool result' do
        summarizer = described_class.new(task)
        expect(summarizer.summarize).to eq("Created 'My Playlist' (ID: xyz789)")
      end
    end

    context 'when tool result has only name' do
      let(:llm_history) do
        [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'tool_use', 'id' => 'tool_1', 'name' => 'create_note' }
            ]
          },
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'tool_1', 'content' => '{"title": "Research Notes"}' }
            ]
          }
        ]
      end

      before do
        allow(task).to receive(:get_llm_history).and_return(llm_history)
      end

      it 'uses title as name' do
        summarizer = described_class.new(task)
        expect(summarizer.summarize).to eq("Created 'Research Notes'")
      end
    end

    context 'when tool result has only id' do
      let(:llm_history) do
        [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'tool_use', 'id' => 'tool_1', 'name' => 'something' }
            ]
          },
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'tool_1', 'content' => '{"id": "abc123"}' }
            ]
          }
        ]
      end

      before do
        allow(task).to receive(:get_llm_history).and_return(llm_history)
      end

      it 'uses id only' do
        summarizer = described_class.new(task)
        expect(summarizer.summarize).to eq("Completed (ID: abc123)")
      end
    end

    context 'when tool result is an error' do
      let(:llm_history) do
        [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'tool_use', 'id' => 'tool_1', 'name' => 'something' }
            ]
          },
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'tool_1', 'content' => 'Error: failed', 'is_error' => true }
            ]
          }
        ]
      end

      before do
        allow(task).to receive(:get_llm_history).and_return(llm_history)
      end

      it 'skips error results and returns default' do
        summarizer = described_class.new(task)
        expect(summarizer.summarize).to eq("Task completed")
      end
    end

    context 'when tool result is not valid JSON' do
      let(:llm_history) do
        [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'tool_use', 'id' => 'tool_1', 'name' => 'something' }
            ]
          },
          {
            'role' => 'user',
            'content' => [
              { 'type' => 'tool_result', 'tool_use_id' => 'tool_1', 'content' => 'just plain text' }
            ]
          }
        ]
      end

      before do
        allow(task).to receive(:get_llm_history).and_return(llm_history)
      end

      it 'returns default summary' do
        summarizer = described_class.new(task)
        expect(summarizer.summarize).to eq("Task completed")
      end
    end

    context 'when an exception is raised during initialization' do
      before do
        allow(task).to receive(:get_llm_history).and_raise(StandardError.new("Database error"))
      end

      it 'returns default summary and logs warning' do
        expect(Rails.logger).to receive(:warn).with(/Failed to load history/)
        summarizer = described_class.new(task)
        expect(summarizer.summarize).to eq("Task completed")
      end
    end

    context 'with very long final text' do
      let(:llm_history) do
        [
          {
            'role' => 'assistant',
            'content' => [
              { 'type' => 'text', 'text' => "A" * 600 }
            ]
          }
        ]
      end

      before do
        allow(task).to receive(:get_llm_history).and_return(llm_history)
      end

      it 'truncates to 500 characters' do
        summarizer = described_class.new(task)
        result = summarizer.summarize
        expect(result.length).to be <= 500
      end
    end
  end

  describe 'JSON parsing' do
    let(:summarizer) { described_class.new(task) }

    before do
      allow(task).to receive(:get_llm_history).and_return([])
    end

    it 'parses simple JSON' do
      result = summarizer.send(:parse_json, '{"id": "123", "name": "Test"}')
      expect(result).to eq({ 'id' => '123', 'name' => 'Test' })
    end

    it 'handles hash input directly' do
      result = summarizer.send(:parse_json, { 'id' => '456' })
      expect(result).to eq({ 'id' => '456' })
    end

    it 'returns nil for non-JSON strings' do
      result = summarizer.send(:parse_json, 'just text')
      expect(result).to be_nil
    end

    it 'returns nil for invalid JSON' do
      result = summarizer.send(:parse_json, '{invalid json}}}')
      expect(result).to be_nil
    end
  end
end
