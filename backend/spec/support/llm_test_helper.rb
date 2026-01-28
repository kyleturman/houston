# frozen_string_literal: true

# LLM Test Helper
# Provides utilities for testing with mocked or real LLMs
#
# Environment Variables:
#   USE_REAL_LLM=true    - Use real LLM API calls (costs money!)
#   MOCK_LLM=true        - Force mock mode (default)
#
# Usage:
#   RSpec.describe 'Something with LLM' do
#     it 'works with mocked LLM', :llm_mock do
#       # LLM calls are automatically mocked
#     end
#
#     it 'works with real LLM', :real_llm do
#       skip_unless_real_llm_enabled
#       # Makes actual API calls
#     end
#   end

module LlmTestHelper
  # Check if real LLM mode is enabled
  def real_llm_enabled?
    ENV['USE_REAL_LLM'] == 'true'
  end

  # Skip test unless real LLM mode is enabled
  def skip_unless_real_llm_enabled
    skip 'Set USE_REAL_LLM=true to run this test' unless real_llm_enabled?
  end

  # Check if we should skip expensive LLM tests
  def skip_expensive_llm?
    !real_llm_enabled?
  end

  # Create a mock LLM response that matches real LLM format
  def mock_llm_response(content:, tool_calls: nil, stop_reason: 'end_turn')
    # Format content as array of content blocks (matches real LLM response)
    content_array = if content.is_a?(String)
      [{ type: 'text', text: content }]
    elsif content.is_a?(Array)
      content
    else
      [{ type: 'text', text: content.to_s }]
    end
    
    {
      content: content_array,
      tool_calls: tool_calls || [],
      stop_reason: stop_reason,
      usage: { input_tokens: 100, output_tokens: 50 }
    }
  end

  # Mock Llms::Service.call to return a specific response
  # Supports streaming when a block is given
  def mock_llm_service_response(response)
    allow(Llms::Service).to receive(:call) do |**args, &block|
      # If block given (streaming), yield text from response content
      if block_given? && response[:content].is_a?(Array)
        response[:content].each do |block_content|
          if block_content[:type] == 'text' || block_content[:type] == :text
            text = block_content[:text] || block_content['text']
            text.to_s.chars.each { |char| block.call(char) } if text
          end
        end
      end
      # Return response
      response
    end
  end

  # Mock goal creation LLM response
  def mock_goal_creation_response(title:, description:, agent_instructions:, learnings: [])
    mock_llm_response(
      content: "Let's create your goal!",
      tool_calls: [
        {
          name: 'finalize_goal_creation',
          parameters: {
            'title' => title,
            'description' => description,
            'agent_instructions' => agent_instructions,
            'learnings' => learnings
          },
          call_id: 'test_call_id'
        }
      ]
    )
  end

  # Mock task execution LLM response
  def mock_task_execution_response(action: 'search', content: 'Working on it...')
    case action
    when 'search'
      mock_llm_response(
        content: content,
        tool_calls: [
          {
            name: 'brave_web_search',
            parameters: { 'query' => 'test query' },
            call_id: 'search_call_id'
          }
        ]
      )
    when 'note'
      mock_llm_response(
        content: content,
        tool_calls: [
          {
            name: 'create_note',
            parameters: {
              'title' => 'Test Note',
              'content' => 'Note content'
            },
            call_id: 'note_call_id'
          }
        ]
      )
    when 'complete'
      mock_llm_response(
        content: content,
        tool_calls: [
          {
            name: 'mark_task_complete',
            parameters: {
              'summary' => 'Task completed',
              'learnings' => ['Learning 1']
            },
            call_id: 'complete_call_id'
          }
        ]
      )
    else
      mock_llm_response(content: content)
    end
  end

  # Mock agent response for goal/task/user_agent orchestrator execution
  def mock_agent_response(status: 'thinking', message: nil, create_task: false, create_note: false)
    tool_calls = []

    if message
      tool_calls << {
        name: 'send_message',
        parameters: { 'text' => message },
        call_id: 'msg_call_id'
      }
    end

    if create_task
      tool_calls << {
        name: 'create_task',
        parameters: {
          'title' => 'Test Task',
          'instructions' => 'Complete this test task with detailed context'
        },
        call_id: 'task_call_id'
      }
    end

    if create_note
      tool_calls << {
        name: 'create_note',
        parameters: {
          'title' => 'Test Note',
          'content' => 'This is a test note with sufficient content to meet the 150-250 word requirement. ' * 10
        },
        call_id: 'note_call_id'
      }
    end

    mock_llm_response(
      content: status == 'complete' ? 'Task completed' : 'Thinking...',
      tool_calls: tool_calls
    )
  end

  # Mock feed generation response
  def mock_feed_generation_response(reflections: 1, discoveries: 1)
    reflection_items = reflections.times.map do |i|
      {
        'prompt' => "Test reflection #{i + 1}?",
        'goal_ids' => ['1', '2'],
        'insight_type' => 'progress_check'
      }
    end

    discovery_items = discoveries.times.map do |i|
      {
        'title' => "Test Discovery #{i + 1}",
        'summary' => 'Relevant resource for your goals',
        'url' => "https://example.com/resource-#{i + 1}",
        'source' => 'web_search',
        'goal_ids' => ['1', '2'],
        'discovery_type' => 'tool'
      }
    end

    mock_llm_response(
      content: 'Generated feed insights',
      tool_calls: [
        {
          name: 'generate_feed_insights',
          parameters: {
            'reflections' => reflection_items,
            'discoveries' => discovery_items
          },
          call_id: 'feed_call_id'
        }
      ]
    )
  end
end

RSpec.configure do |config|
  config.include LlmTestHelper

  # Tag tests that use real LLM - requires USE_REAL_LLM=true
  # Also enables real HTTP connections (WebMock blocks them by default)
  config.before(:each, :real_llm) do
    skip 'Set USE_REAL_LLM=true to run real LLM tests' unless ENV['USE_REAL_LLM'] == 'true'
    WebMock.allow_net_connect!
  end

  config.after(:each, :real_llm) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  # Automatically mock LLM calls unless explicitly using real LLM
  config.before(:each) do |example|
    # Skip mocking for fast contract tests (they don't load Rails)
    next if example.metadata[:fast]

    # Skip mocking if test is tagged :real_llm AND USE_REAL_LLM=true
    use_real_llm = ENV['USE_REAL_LLM'] == 'true'
    has_real_llm_tag = example.metadata[:real_llm]
    skip_adapter_mock = example.metadata[:skip_adapter_mock]

    # Skip mocking if using real LLM
    next if use_real_llm && has_real_llm_tag

    # Mock LLM service by default
    allow(Llms::Service).to receive(:call).and_return(
      mock_llm_response(content: 'Mocked response')
    )
    
    # Also mock adapter.call for CoreLoop and direct adapter usage
    # Skip if test is testing the adapter factory itself
    unless skip_adapter_mock
      mock_adapter = double('MockAdapter')
      allow(mock_adapter).to receive(:call).and_return({
        'content' => [{ 'type' => 'text', 'text' => 'Mocked adapter response' }],
        'stop_reason' => 'end_turn',
        '_usage' => { 'input_tokens' => 10, 'output_tokens' => 20 }
      })
      allow(mock_adapter).to receive(:extract_tool_calls).and_return([])
      allow(mock_adapter).to receive(:format_tool_results).and_return([])
      allow(Llms::Adapters).to receive(:for).and_return(mock_adapter)
    end
  end
end
