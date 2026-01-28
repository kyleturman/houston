# frozen_string_literal: true

module Llms
  # ENV Configuration (REQUIRED):
  #   LLM_AGENTS_MODEL=anthropic:sonnet-4.5
  #   LLM_TASKS_MODEL=anthropic:haiku-4.5
  #   LLM_SUMMARIES_MODEL=anthropic:haiku-4.5
  #   ANTHROPIC_API_KEY=sk-...
  #   OPENAI_API_KEY=sk-...
  #   OPENROUTER_API_KEY=sk-or-...         # For OpenRouter (400+ models)
  #   OLLAMA_API_KEY=optional              # Ollama typically doesn't need auth
  #
  # Example configurations:
  #   LLM_AGENTS_MODEL=openrouter:anthropic/claude-3-opus
  #   LLM_AGENTS_MODEL=openrouter:meta-llama/llama-3.3-70b-instruct
  #   LLM_AGENTS_MODEL=ollama:llama3.3
  #   LLM_TASKS_MODEL=openrouter:openai/gpt-4o
  #
  # Optional OpenRouter cost tracking:
  #   OPENROUTER_INPUT_COST=0.60           # per 1M tokens (defaults to 0)
  #   OPENROUTER_OUTPUT_COST=0.60          # per 1M tokens (defaults to 0)
  #
  # Optional Ollama configuration:
  #   OLLAMA_BASE_URL=http://localhost:11434  # defaults to localhost
  #
  module Adapters
    class ConfigurationError < StandardError; end
    
    # Main interface - get adapter for use case with optional cost tracking
    def self.for(use_case, user: nil, agentable: nil, context: nil)
      provider, model = parse_config_for_use_case(use_case)
      validate_api_key!(provider)
      
      adapter = build_adapter(provider, model)
      adapter.setup_tracking(user: user, agentable: agentable, context: context)
    end
    
    # Get specific adapter by provider and model
    def self.get(provider, model = nil, user: nil, agentable: nil, context: nil)
      validate_api_key!(provider)
      
      adapter = build_adapter(provider, model)
      adapter.setup_tracking(user: user, agentable: agentable, context: context)
    end
    
    private
    
    # Parse ENV like "anthropic:sonnet-4.5"
    def self.parse_config_for_use_case(use_case)
      env_key = case use_case
                when :agents then 'LLM_AGENTS_MODEL'
                when :tasks then 'LLM_TASKS_MODEL'
                when :summaries then 'LLM_SUMMARIES_MODEL'
                else
                  raise ConfigurationError, "Unknown use case: #{use_case}. Must be :agents, :tasks, or :summaries"
                end
      
      config = ENV[env_key]
      raise ConfigurationError, "#{env_key} not set. Required format: provider:model (e.g., anthropic:sonnet-4.5)" unless config
      
      unless config.include?(':')
        raise ConfigurationError, "#{env_key} must be in format 'provider:model' (e.g., anthropic:sonnet-4.5), got: #{config}"
      end
      
      parts = config.split(':', 2)
      provider = parts[0].to_sym
      model = parts[1]
      
      raise ConfigurationError, "Model not specified in #{env_key}: #{config}" if model.blank?
      
      [provider, model]
    end
    
    def self.validate_api_key!(provider)
      # Convention: PROVIDER_API_KEY (e.g., ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY)
      # Some providers like Ollama don't require API keys (local inference)
      providers_without_required_keys = [:ollama]
      return if providers_without_required_keys.include?(provider)

      env_key = "#{provider.to_s.upcase}_API_KEY"

      unless ENV[env_key].present?
        raise ConfigurationError, "#{env_key} not set. Required for #{provider} provider."
      end
    end
    
    def self.build_adapter(provider, model = nil)
      # Convention: adapters/provider_adapter.rb defines ProviderAdapter class
      # File: anthropic_adapter.rb -> Class: AnthropicAdapter
      # File: openai_adapter.rb -> Class: OpenAIAdapter (special case)
      # File: google_adapter.rb -> Class: GoogleAdapter
      adapter_file = "adapters/#{provider}_adapter"
      
      # Handle special cases for class names (e.g., OpenAI not Openai)
      adapter_class_name = case provider.to_s
                          when 'openai' then 'OpenAIAdapter'
                          else "#{provider.to_s.classify}Adapter"
                          end
      
      begin
        require_relative adapter_file
      rescue LoadError
        raise ConfigurationError, "No adapter found for provider '#{provider}'. Expected file: #{adapter_file}.rb"
      end
      
      begin
        adapter_class = "Llms::Adapters::#{adapter_class_name}".constantize
      rescue NameError
        raise ConfigurationError, "Adapter class #{adapter_class_name} not found in #{adapter_file}.rb"
      end
      
      adapter_class.new(model: model)
    end
  end
end
