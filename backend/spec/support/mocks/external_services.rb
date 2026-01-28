# frozen_string_literal: true

# Default stubs for external services to keep tests fast and deterministic.
# Tests can opt-in to real services with :real_llm tag
RSpec.configure do |config|
  config.before(:each) do |example|
    # Skip mocking for tests explicitly tagged with :real_llm
    next if example.metadata[:real_llm]

    # Stub LLM service outbound calls
    if defined?(Llms::Service)
      # New unified API - supports streaming
      allow(Llms::Service).to receive(:call) do |**args, &block|
        # If block given (streaming), yield some text chunks
        if block_given?
          'stubbed response'.chars.each { |char| block.call(char) }
        end
        # Return result
        {
          content: [{ type: :text, text: 'stubbed response' }],
          tool_calls: [],
          usage: {}
        }
      end

      allow(Llms::Service).to receive(:agent_call) do |**args, &block|
        puts "🔴 [MOCK] Service.agent_call called - returning mock result"
        # Yield some events if block given
        if block_given?
          puts "   └─ Yielding mock :think event"
          block.call({ type: :think, data: { text: 'stubbed thinking' } })
        end
        # Return result
        {
          response: { 'content' => [{ 'type' => 'text', 'text' => 'stubbed agent response' }] },
          tool_calls: [],
          policy: Tools::Policy.new,
          streamed_text: 'stubbed agent response'
        }
      end
    end

    # Anthropic adapter stubs - unified call interface
    if defined?(Llms::Adapters::AnthropicAdapter)
      allow_any_instance_of(Llms::Adapters::AnthropicAdapter).to receive(:make_request) do |&block|
        # If block given (streaming), yield some text then return response
        if block_given?
          block.call('stubbed ')
          block.call('anthropic ')
          block.call('response')
        end
        # Return response
        {
          'content' => [{ 'type' => 'text', 'text' => 'stubbed anthropic response' }],
          '_usage' => { 'input_tokens' => 100, 'output_tokens' => 50 }
        }
      end
    end

    # MCP server discovery stubs
    if defined?(Mcp::ConnectionManager)
      allow_any_instance_of(Mcp::ConnectionManager).to receive(:list_servers).and_return({})
      allow_any_instance_of(Mcp::ConnectionManager).to receive(:reload!).and_return(true)
    end

    # Redis pub/sub stubs if needed
    if defined?(Streams::Broker)
      allow(Streams::Broker).to receive(:publish).and_return(true)
      allow(Streams::Broker).to receive(:subscribe).and_yield(->(_event, _data) {})
    end

    # Streams::Broadcaster stubs (for SSE broadcasting)
    # Stub is loaded from spec/support/stubs/streams_broadcaster_stub.rb
    allow(Streams::Broadcaster).to receive(:broadcast_resource_created).and_return(true)
    allow(Streams::Broadcaster).to receive(:broadcast_resource_updated).and_return(true)
    allow(Streams::Broadcaster).to receive(:broadcast_resource_destroyed).and_return(true)

    # Sidekiq job stubs
    # In inline mode, perform_in/perform_async immediately call #perform on a new instance
    # So we mock #perform to return immediately without executing the real orchestrator
    if defined?(Agents::Orchestrator)
      allow_any_instance_of(Agents::Orchestrator).to receive(:perform).and_wrap_original do |method, *args|
        puts "🔵 [MOCK] Orchestrator#perform called - skipping execution"
        true
      end
    end
    
    # CoreLoop stubs - prevent actual agent execution in tests
    if defined?(Agents::CoreLoop)
      allow_any_instance_of(Agents::CoreLoop).to receive(:run!).and_wrap_original do |method, **args|
        puts "🔴 [MOCK] CoreLoop.run! called - returning immediately without execution"
        { iterations: 1, natural_completion: true }
      end
    end
  end
end
