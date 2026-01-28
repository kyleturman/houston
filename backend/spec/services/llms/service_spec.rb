# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llms::Service do
  describe 'LLM provider connectivity', :provider, :real_llm do
    before do
      # Verify required ENV vars are set
      unless ENV['LLM_AGENTS_MODEL'] && !ENV['LLM_AGENTS_MODEL'].empty?
        skip 'LLM provider test requires LLM_AGENTS_MODEL to be set'
      end
    end
    
    it 'successfully connects to LLM provider and makes a simple call' do
      skip_unless_real_llm_enabled
      
      puts "\n=== Testing LLM Provider Connectivity ==="
      puts "This is the cheapest possible LLM test (~$0.001)"
      puts "Testing basic connectivity without complex logic"
      puts "Model: #{ENV['LLM_AGENTS_MODEL']}"
      
      # Make the simplest possible LLM call (matches actual usage)
      result = described_class.call(
        system: "You are a test assistant. Respond briefly.",
        messages: [
          { 
            role: 'user', 
            content: [{ 
              type: 'text', 
              text: 'Say hello in exactly 3 words.' 
            }] 
          }
        ],
        tools: []
      )
      
      # Verify we got a response
      expect(result).to be_present
      expect(result[:content]).to be_a(Array)
      expect(result[:content].length).to be > 0
      
      # Verify response structure
      first_item = result[:content].first
      expect(first_item[:type]).to eq(:text).or eq('text')
      expect(first_item[:text]).to be_a(String)
      expect(first_item[:text].length).to be > 0
      
      puts "✅ LLM provider responding correctly"
      puts "Response: #{first_item[:text]}"
      puts "=== Provider Test Complete ==="
      
      # Verify it's actually a reasonable response
      expect(first_item[:text].downcase).to include('hello').or include('hi')
    end
    
    it 'handles tool definitions without errors' do
      skip_unless_real_llm_enabled
      
      puts "\n=== Testing Tool Definition Handling ==="
      
      # Test with a simple tool definition
      result = described_class.call(
        system: "You are a test assistant.",
        messages: [
          { 
            role: 'user', 
            content: [{ 
              type: 'text', 
              text: 'Just say "tools work" without using any tools.' 
            }] 
          }
        ],
        tools: [
          {
            name: 'test_tool',
            description: 'A test tool that should not be called',
            input_schema: {
              type: 'object',
              properties: {
                message: { type: 'string', description: 'Test message' }
              },
              required: ['message']
            }
          }
        ]
      )
      
      # Verify we got a text response, not a tool call
      expect(result[:content]).to be_present
      text_item = result[:content].find { |item| item[:type] == :text || item[:type] == 'text' }
      expect(text_item).to be_present, "Should have a text response block"
      expect(text_item[:text]).to be_present, "Text block should have content"
      
      puts "✅ Tool definitions handled correctly"
      puts "Response: #{text_item[:text]}"
      puts "=== Tool Definition Test Complete ==="
    end
    
    it 'successfully calls tools when instructed' do
      skip_unless_real_llm_enabled
      
      puts "\n=== Testing Actual Tool Use ==="
      puts "This verifies the LLM can call tools correctly"
      
      tools = [
        {
          name: 'get_weather',
          description: 'Get the current weather for a location',
          input_schema: {
            type: 'object',
            properties: {
              location: { 
                type: 'string', 
                description: 'The city name, e.g. San Francisco' 
              }
            },
            required: ['location']
          }
        }
      ]
      
      messages = [
        { 
          role: 'user', 
          content: [{ 
            type: 'text', 
            text: 'What is the weather in San Francisco?' 
          }] 
        }
      ]
      
      system = "You are a helpful assistant. Use the get_weather tool to answer weather questions."
      
      # Test both non-streaming and streaming modes
      [false, true].each do |use_streaming|
        mode = use_streaming ? "streaming" : "non-streaming"
        puts "\n--- Testing #{mode} mode ---"
        
        result = if use_streaming
          # Streaming mode (used by agent_call)
          # Note: When tools are present, text isn't yielded to the block
          # The streaming happens internally to build the response
          described_class.call(
            system: system,
            messages: messages,
            tools: tools,
            stream: true
          ) { |chunk| } # Block required to enable streaming
        else
          # Non-streaming mode
          described_class.call(
            system: system,
            messages: messages,
            tools: tools
          )
        end
        
        # Verify we got a tool call
        expect(result).to be_present, "#{mode}: Should have result"
        expect(result[:tool_calls]).to be_present, "#{mode}: Should have tool_calls in response"
        expect(result[:tool_calls]).to be_an(Array), "#{mode}: tool_calls should be an array"
        expect(result[:tool_calls].length).to be > 0, "#{mode}: Should have at least one tool call"
        
        tool_call = result[:tool_calls].first
        
        # Canonical format from standardize_tool_call: { name:, parameters:, call_id: }
        expect(tool_call[:name]).to eq('get_weather'), "#{mode}: Tool name should be get_weather"
        expect(tool_call[:parameters]).to be_a(Hash), "#{mode}: Parameters should be a hash"
        expect(tool_call[:call_id]).to be_present, "#{mode}: Call ID should be present"
        
        location = tool_call[:parameters]['location'] || tool_call[:parameters][:location]
        expect(location).to be_present, "#{mode}: Location parameter should be present"
        expect(location.downcase).to include('san francisco').or(include('sf')), "#{mode}: Location should be San Francisco"
        
        # Verify tool call structure matches what iOS tool cells expect
        # iOS tool cells expect: { name:, parameters:, call_id: }
        # This is the canonical format from standardize_tool_call
        puts "✅ #{mode.capitalize} tool call successful!"
        puts "   Tool: #{tool_call[:name]}"
        puts "   Location: #{location}"
        puts "   Tool ID: #{tool_call[:call_id]}"
        puts "   Parameters: #{tool_call[:parameters].keys.join(', ')}"
        
        # Verify the structure is exactly what iOS expects
        expect(tool_call.keys.sort).to eq([:call_id, :name, :parameters].sort), 
          "#{mode}: Tool call should have exactly :name, :parameters, :call_id keys"
      end
      
      puts "=== Tool Use Test Complete ==="
    end
    
    it 'provides tool metadata consistent with iOS tool cell expectations' do
      skip_unless_real_llm_enabled
      
      puts "\n=== Testing Tool Metadata Format ==="
      puts "This verifies tool calls match iOS ToolHandler protocol expectations"
      
      # iOS ToolHandler expects metadata with:
      # - status: "in_progress" | "completed" | "failed"
      # - input: { ...parameters }
      # - result: { ...tool result }
      # - id: tool activity ID
      # - name: tool name
      
      tools = [{
        name: 'get_weather',
        description: 'Get weather',
        input_schema: {
          type: 'object',
          properties: { location: { type: 'string' } },
          required: ['location']
        }
      }]
      
      result = described_class.call(
        system: "Use get_weather tool",
        messages: [{ role: 'user', content: [{ type: 'text', text: 'Weather in NYC?' }] }],
        tools: tools,
        stream: true
      ) { |chunk| }
      
      tool_call = result[:tool_calls].first
      
      # Verify canonical format
      expect(tool_call).to have_key(:name)
      expect(tool_call).to have_key(:parameters)
      expect(tool_call).to have_key(:call_id)
      
      # Simulate what would be in ThreadMessage metadata.tool_activity
      simulated_metadata = {
        'id' => tool_call[:call_id],
        'name' => tool_call[:name],
        'status' => 'in_progress',  # Initial state
        'input' => tool_call[:parameters]
      }
      
      # Verify iOS can parse this
      expect(simulated_metadata['id']).to be_present
      expect(simulated_metadata['name']).to be_present
      expect(simulated_metadata['status']).to be_in(['in_progress', 'completed', 'failed'])
      expect(simulated_metadata['input']).to be_a(Hash)
      
      puts "✅ Tool metadata format verified"
      puts "   ID: #{simulated_metadata['id']}"
      puts "   Name: #{simulated_metadata['name']}"
      puts "   Status: #{simulated_metadata['status']}"
      puts "   Input keys: #{simulated_metadata['input'].keys.join(', ')}"
      puts "=== Tool Metadata Test Complete ==="
    end
  end
  
  describe 'mocked provider (fast tests)', :no_real_llm do
    it 'uses mocked responses when not in real LLM mode' do
      # This test runs with mocked LLM by default
      # Verifies the mocking infrastructure works
      
      result = described_class.call(
        system: "Test system prompt",
        messages: [
          { 
            role: 'user', 
            content: [{ type: 'text', text: 'Test message' }] 
          }
        ],
        tools: []
      )
      
      # Should get mocked response
      expect(result).to be_present
      expect(result[:content]).to be_a(Array)
      
      # Mocked responses should have consistent structure
      expect(result[:content].first).to have_key(:type)
      expect(result[:content].first).to have_key(:text)
    end
  end
end
