# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tools Streaming Behavior', :service, :tool, :streaming, :fast do
  # Mock streaming behavior for tools
  let(:streaming_manager) do
    Class.new do
      def initialize
        @events = []
        @subscribers = []
      end

      def publish(channel, event:, data:)
        event_record = {
          channel: channel,
          event: event,
          data: data,
          timestamp: Time.now.iso8601
        }
        @events << event_record
        
        # Notify subscribers
        @subscribers.each { |sub| sub.call(event_record) }
      end

      def subscribe(channel, &block)
        @subscribers << block
      end

      def events
        @events
      end

      def events_for_channel(channel)
        @events.select { |e| e[:channel] == channel }
      end

      def clear_events
        @events.clear
      end
    end.new
  end

  let(:mock_tool_class) do
    Class.new do
      def initialize(streaming_manager:, channel:)
        @streaming_manager = streaming_manager
        @channel = channel
      end

      def execute_with_streaming(tool_name:, tool_id:, **params)
        # Emit tool start
        @streaming_manager.publish(@channel, 
          event: :tool_start, 
          data: { tool_name: tool_name, tool_id: tool_id, started_at: Time.now.iso8601 }
        )

        # Simulate tool execution
        result = case tool_name
        when 'create_note'
          { success: true, note_id: 'note_123', title: params[:title] }
        when 'brave_web_search'
          { success: true, results: [{ title: 'Result 1', url: 'https://example.com' }] }
        when 'send_message'
          { success: true, message_id: 'msg_123' }
        else
          { success: false, error: 'Unknown tool' }
        end

        # Emit progress updates
        @streaming_manager.publish(@channel,
          event: :tool_progress,
          data: { tool_name: tool_name, tool_id: tool_id, progress: 'Processing...' }
        )

        # Emit completion
        @streaming_manager.publish(@channel,
          event: :tool_completion,
          data: { 
            tool_name: tool_name, 
            tool_id: tool_id, 
            status: result[:success] ? 'success' : 'error',
            result: result,
            completed_at: Time.now.iso8601
          }
        )

        result
      end
    end
  end

  describe 'tool execution streaming' do
    it 'emits tool_start event when tool begins' do
      tool = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      
      tool.execute_with_streaming(tool_name: 'create_note', tool_id: 'tool_1', title: 'Test Note')
      
      start_events = streaming_manager.events.select { |e| e[:event] == :tool_start }
      expect(start_events.length).to eq(1)
      
      start_event = start_events.first
      expect(start_event[:data][:tool_name]).to eq('create_note')
      expect(start_event[:data][:tool_id]).to eq('tool_1')
      expect(start_event[:data][:started_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it 'emits tool_progress events during execution' do
      tool = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      
      tool.execute_with_streaming(tool_name: 'brave_web_search', tool_id: 'tool_2', query: 'test query')
      
      progress_events = streaming_manager.events.select { |e| e[:event] == :tool_progress }
      expect(progress_events.length).to eq(1)
      
      progress_event = progress_events.first
      expect(progress_event[:data][:tool_name]).to eq('brave_web_search')
      expect(progress_event[:data][:tool_id]).to eq('tool_2')
      expect(progress_event[:data][:progress]).to eq('Processing...')
    end

    it 'emits tool_completion event when tool finishes' do
      tool = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      
      result = tool.execute_with_streaming(tool_name: 'send_message', tool_id: 'tool_3', content: 'Hello')
      
      completion_events = streaming_manager.events.select { |e| e[:event] == :tool_completion }
      expect(completion_events.length).to eq(1)
      
      completion_event = completion_events.first
      expect(completion_event[:data][:tool_name]).to eq('send_message')
      expect(completion_event[:data][:tool_id]).to eq('tool_3')
      expect(completion_event[:data][:status]).to eq('success')
      expect(completion_event[:data][:result]).to eq(result)
      expect(completion_event[:data][:completed_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it 'maintains correct event ordering' do
      tool = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      
      tool.execute_with_streaming(tool_name: 'create_note', tool_id: 'tool_4', title: 'Ordered Test')
      
      events = streaming_manager.events_for_channel('goal_1')
      expect(events.length).to eq(3)
      
      expect(events[0][:event]).to eq(:tool_start)
      expect(events[1][:event]).to eq(:tool_progress)
      expect(events[2][:event]).to eq(:tool_completion)
      
      # Verify all events have same tool_id
      events.each do |event|
        expect(event[:data][:tool_id]).to eq('tool_4')
      end
    end

    it 'handles tool execution errors in streaming' do
      tool = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      
      result = tool.execute_with_streaming(tool_name: 'unknown_tool', tool_id: 'tool_5')
      
      completion_event = streaming_manager.events.find { |e| e[:event] == :tool_completion }
      expect(completion_event[:data][:status]).to eq('error')
      expect(completion_event[:data][:result][:success]).to be false
      expect(completion_event[:data][:result][:error]).to eq('Unknown tool')
    end
  end

  describe 'streaming channel isolation' do
    it 'isolates events by channel' do
      tool1 = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      tool2 = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_2')
      
      tool1.execute_with_streaming(tool_name: 'create_note', tool_id: 'tool_1', title: 'Goal 1 Note')
      tool2.execute_with_streaming(tool_name: 'send_message', tool_id: 'tool_2', content: 'Goal 2 Message')
      
      goal1_events = streaming_manager.events_for_channel('goal_1')
      goal2_events = streaming_manager.events_for_channel('goal_2')
      
      expect(goal1_events.length).to eq(3)
      expect(goal2_events.length).to eq(3)
      
      # Verify events are properly isolated
      goal1_events.each { |e| expect(e[:channel]).to eq('goal_1') }
      goal2_events.each { |e| expect(e[:channel]).to eq('goal_2') }
    end
  end

  describe 'streaming subscription system' do
    it 'notifies subscribers of events' do
      received_events = []
      
      streaming_manager.subscribe('goal_1') do |event|
        received_events << event
      end
      
      tool = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      tool.execute_with_streaming(tool_name: 'create_note', tool_id: 'tool_1', title: 'Subscribed Note')
      
      expect(received_events.length).to eq(3)
      expect(received_events[0][:event]).to eq(:tool_start)
      expect(received_events[1][:event]).to eq(:tool_progress)
      expect(received_events[2][:event]).to eq(:tool_completion)
    end

    it 'supports multiple subscribers' do
      subscriber1_events = []
      subscriber2_events = []
      
      streaming_manager.subscribe('goal_1') { |event| subscriber1_events << event }
      streaming_manager.subscribe('goal_1') { |event| subscriber2_events << event }
      
      tool = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      tool.execute_with_streaming(tool_name: 'send_message', tool_id: 'tool_1', content: 'Multi-subscriber test')
      
      expect(subscriber1_events.length).to eq(3)
      expect(subscriber2_events.length).to eq(3)
      expect(subscriber1_events).to eq(subscriber2_events)
    end
  end

  describe 'streaming event structure validation' do
    it 'includes required metadata in all events' do
      tool = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      
      tool.execute_with_streaming(tool_name: 'create_note', tool_id: 'tool_1', title: 'Metadata Test')
      
      streaming_manager.events.each do |event|
        expect(event).to have_key(:channel)
        expect(event).to have_key(:event)
        expect(event).to have_key(:data)
        expect(event).to have_key(:timestamp)
        
        expect(event[:data]).to have_key(:tool_name)
        expect(event[:data]).to have_key(:tool_id)
        expect(event[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    it 'includes execution-specific data in completion events' do
      tool = mock_tool_class.new(streaming_manager: streaming_manager, channel: 'goal_1')
      
      tool.execute_with_streaming(tool_name: 'brave_web_search', tool_id: 'tool_1', query: 'test')
      
      completion_event = streaming_manager.events.find { |e| e[:event] == :tool_completion }
      completion_data = completion_event[:data]
      
      expect(completion_data).to have_key(:status)
      expect(completion_data).to have_key(:result)
      expect(completion_data).to have_key(:completed_at)
      expect(completion_data[:result]).to have_key(:success)
    end
  end
end
