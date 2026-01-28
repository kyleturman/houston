# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llms::Adapters do
  # Set required API keys for tests
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-anthropic-key')
    allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-openai-key')
    allow(ENV).to receive(:[]).with('OPENROUTER_API_KEY').and_return('test-openrouter-key')
    allow(ENV).to receive(:[]).with('OLLAMA_API_KEY').and_return(nil)  # Ollama doesn't require key
  end
  
  describe '.get with Anthropic' do
    it 'creates anthropic adapter with sonnet' do
      adapter = Llms::Adapters.get(:anthropic, 'sonnet-4.5')

      expect(adapter).to be_a(Llms::Adapters::AnthropicAdapter)
      expect(adapter.provider).to eq(:anthropic)
      expect(adapter.model_key).to eq('sonnet-4.5')
      expect(adapter.api_model_id).to eq('claude-sonnet-4-5')
    end
    
    it 'calculates sonnet cost correctly' do
      adapter = Llms::Adapters.get(:anthropic, 'sonnet-4.5')
      cost = adapter.calculate_cost(input_tokens: 1000, output_tokens: 500)
      expect(cost.round(6)).to eq(0.0105)
    end

    it 'calculates sonnet cost with cache writes correctly' do
      adapter = Llms::Adapters.get(:anthropic, 'sonnet-4.5')
      # 500 regular input + 1000 cache write + 500 output
      # = (500/1M * $3) + (1000/1M * $3.75) + (500/1M * $15)
      # = $0.0015 + $0.00375 + $0.0075 = $0.01275
      cost = adapter.calculate_cost(
        input_tokens: 1500,
        output_tokens: 500,
        cache_creation_input_tokens: 1000
      )
      expect(cost.round(6)).to eq(0.01275)
    end

    it 'calculates sonnet cost with cache reads correctly' do
      adapter = Llms::Adapters.get(:anthropic, 'sonnet-4.5')
      # 500 regular input + 1000 cache read + 500 output
      # = (500/1M * $3) + (1000/1M * $0.30) + (500/1M * $15)
      # = $0.0015 + $0.0003 + $0.0075 = $0.0093
      cost = adapter.calculate_cost(
        input_tokens: 1500,
        output_tokens: 500,
        cache_read_input_tokens: 1000
      )
      expect(cost.round(6)).to eq(0.0093)
    end
    
    it 'creates anthropic adapter with haiku' do
      adapter = Llms::Adapters.get(:anthropic, 'haiku-4.5')

      expect(adapter).to be_a(Llms::Adapters::AnthropicAdapter)
      expect(adapter.model_key).to eq('haiku-4.5')
      expect(adapter.api_model_id).to eq('claude-haiku-4-5')
    end
  end
  
  describe '.get with OpenAI' do
    it 'creates openai adapter with gpt-5' do
      adapter = Llms::Adapters.get(:openai, 'gpt-5')

      expect(adapter).to be_a(Llms::Adapters::OpenAIAdapter)
      expect(adapter.provider).to eq(:openai)
      expect(adapter.model_key).to eq('gpt-5')
      expect(adapter.api_model_id).to eq('gpt-5')
    end

    it 'creates openai adapter with gpt-5-nano' do
      adapter = Llms::Adapters.get(:openai, 'gpt-5-nano')

      expect(adapter).to be_a(Llms::Adapters::OpenAIAdapter)
      expect(adapter.model_key).to eq('gpt-5-nano')
      expect(adapter.api_model_id).to eq('gpt-5-nano')
    end

    it 'calculates gpt-5 cost correctly' do
      adapter = Llms::Adapters.get(:openai, 'gpt-5')
      cost = adapter.calculate_cost(input_tokens: 1000, output_tokens: 500)
      # (1000/1M * $1.25) + (500/1M * $10) = $0.00125 + $0.005 = $0.00625
      expect(cost.round(6)).to eq(0.00625)
    end

    it 'calculates gpt-5-nano cost correctly' do
      adapter = Llms::Adapters.get(:openai, 'gpt-5-nano')
      cost = adapter.calculate_cost(input_tokens: 1000, output_tokens: 500)
      # (1000/1M * $0.05) + (500/1M * $0.40) = $0.00005 + $0.0002 = $0.00025
      expect(cost.round(6)).to eq(0.00025)
    end

    it 'calculates gpt-5 cost with cache reads correctly' do
      adapter = Llms::Adapters.get(:openai, 'gpt-5')
      # 500 regular input + 1000 cached + 500 output
      # = (500/1M * $1.25) + (1000/1M * $0.125) + (500/1M * $10)
      # = $0.000625 + $0.000125 + $0.005 = $0.00575
      cost = adapter.calculate_cost(
        input_tokens: 1500,
        output_tokens: 500,
        cached_tokens: 1000
      )
      expect(cost.round(6)).to eq(0.00575)
    end
  end

  describe '.get with OpenRouter' do
    it 'creates openrouter adapter with custom model' do
      adapter = Llms::Adapters.get(:openrouter, 'meta-llama/llama-3.3-70b-instruct')

      expect(adapter).to be_a(Llms::Adapters::OpenrouterAdapter)
      expect(adapter.provider).to eq(:openrouter)
      expect(adapter.model_key).to eq('meta-llama/llama-3.3-70b-instruct')
      expect(adapter.api_model_id).to eq('meta-llama/llama-3.3-70b-instruct')
    end

    it 'creates openrouter adapter with different model' do
      adapter = Llms::Adapters.get(:openrouter, 'anthropic/claude-3-opus')

      expect(adapter).to be_a(Llms::Adapters::OpenrouterAdapter)
      expect(adapter.model_key).to eq('anthropic/claude-3-opus')
      expect(adapter.api_model_id).to eq('anthropic/claude-3-opus')
    end

    it 'calculates zero cost by default' do
      adapter = Llms::Adapters.get(:openrouter, 'meta-llama/llama-3.3-70b-instruct')
      cost = adapter.calculate_cost(input_tokens: 1000, output_tokens: 500)
      expect(cost).to eq(0.0)
    end

    it 'calculates cost when ENV vars are set' do
      allow(ENV).to receive(:[]).with('OPENROUTER_INPUT_COST').and_return('0.60')
      allow(ENV).to receive(:[]).with('OPENROUTER_OUTPUT_COST').and_return('0.60')

      adapter = Llms::Adapters.get(:openrouter, 'meta-llama/llama-3.3-70b-instruct')
      cost = adapter.calculate_cost(input_tokens: 1000, output_tokens: 500)
      # (1000/1M * $0.60) + (500/1M * $0.60) = $0.0006 + $0.0003 = $0.0009
      expect(cost.round(6)).to eq(0.0009)
    end
  end

  describe '.get with Ollama' do
    it 'creates ollama adapter with default model' do
      adapter = Llms::Adapters.get(:ollama, 'llama3.3')

      expect(adapter).to be_a(Llms::Adapters::OllamaAdapter)
      expect(adapter.provider).to eq(:ollama)
      expect(adapter.model_key).to eq('llama3.3')
      expect(adapter.api_model_id).to eq('llama3.3')
    end

    it 'creates ollama adapter with custom model' do
      adapter = Llms::Adapters.get(:ollama, 'qwen2.5:72b')

      expect(adapter).to be_a(Llms::Adapters::OllamaAdapter)
      expect(adapter.model_key).to eq('qwen2.5:72b')
      expect(adapter.api_model_id).to eq('qwen2.5:72b')
    end

    it 'calculates zero cost for local models' do
      adapter = Llms::Adapters.get(:ollama, 'llama3.3')
      cost = adapter.calculate_cost(input_tokens: 1000, output_tokens: 500)
      expect(cost).to eq(0.0)
    end
  end
end
