# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llms::Prompts::AgentHistory do
  describe '.user_prompt' do
    it 'includes user messages' do
      history = [
        {'role' => 'user', 'content' => 'Test message'}
      ]

      result = described_class.user_prompt(llm_history: history, tool_names: [])
      expect(result).to include('- Test message')
    end

    it 'includes summarization instructions' do
      history = [
        {'role' => 'user', 'content' => 'Test message'}
      ]

      result = described_class.user_prompt(llm_history: history, tool_names: [])
      expect(result).to include('Summarize this conversation')
      expect(result).to include('ONE sentence')
    end

    it 'handles multiple user messages' do
      history = [
        {'role' => 'user', 'content' => 'First message'},
        {'role' => 'assistant', 'content' => 'Response'},
        {'role' => 'user', 'content' => 'Second message'}
      ]

      result = described_class.user_prompt(llm_history: history, tool_names: [])
      expect(result).to include('- First message')
    end

    it 'handles array content in user messages' do
      history = [
        {
          'role' => 'user',
          'content' => [
            {'type' => 'text', 'text' => 'Array content message'}
          ]
        }
      ]

      result = described_class.user_prompt(llm_history: history, tool_names: [])
      expect(result).to include('- Array content message')
    end
  end

  describe '.system_prompt' do
    it 'describes the task' do
      result = described_class.system_prompt
      expect(result).to include('Summarize the KEY CONTEXT')
    end

    it 'includes format guidance' do
      result = described_class.system_prompt
      expect(result).to include('one-sentence')
      expect(result).to include('User asked about')
    end

    it 'includes examples of good summaries' do
      result = described_class.system_prompt
      expect(result).to include('GOOD summaries')
    end

    it 'includes examples of bad summaries' do
      result = described_class.system_prompt
      expect(result).to include('WRONG')
    end
  end
end
