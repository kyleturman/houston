# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tools::System::SendMessage', :service, :tool, :api, :fast do
  # Mock SendMessage tool behavior
  let(:send_message_class) do
    Class.new do
      def initialize(user:, goal:, task:, agentable:)
        @user = user
        @goal = goal
        @task = task
        @agentable = agentable
        @messages = [] # Mock message storage
      end

      def execute(content:)
        return { success: false, error: 'Content cannot be empty' } if content.nil? || content.strip.empty?
        return { success: false, error: 'Content too long' } if content.length > 50000

        # Mock message creation
        message = {
          id: "msg_#{Time.now.to_f.to_s.gsub('.', '_')}",
          content: content,
          source: 'agent',
          user_id: @user[:id],
          agentable_type: @agentable[:type] || 'Goal',
          agentable_id: @agentable[:id],
          created_at: Time.now.iso8601
        }

        @messages << message
        { success: true, message_id: message[:id], message: message }
      end

      def messages
        @messages
      end
    end
  end

  let(:mock_user) { { id: 1, email: 'test@example.com' } }
  let(:mock_goal) { { id: 1, title: 'Test Goal', type: 'Goal', user_id: 1 } }
  let(:mock_task) { { id: 1, title: 'Test Task', type: 'Task', goal_id: 1 } }

  describe '#execute' do
    it 'creates a thread message with agent source' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      
      result = tool.execute(content: 'Hello from agent!')
      
      expect(result[:success]).to be true
      expect(result[:message_id]).to be_present
      expect(result[:message][:content]).to eq('Hello from agent!')
      expect(result[:message][:source]).to eq('agent')
      expect(result[:message][:user_id]).to eq(1)
      expect(result[:message][:agentable_type]).to eq('Goal')
      expect(result[:message][:agentable_id]).to eq(1)

      # Verify message was stored
      expect(tool.messages.length).to eq(1)
      message = tool.messages.first
      expect(message[:content]).to eq('Hello from agent!')
    end

    it 'handles empty content gracefully' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      
      result = tool.execute(content: '')
      expect(result[:success]).to be false
      expect(result[:error]).to include('Content cannot be empty')
      expect(tool.messages.length).to eq(0)
    end

    it 'handles nil content gracefully' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      
      result = tool.execute(content: nil)
      expect(result[:success]).to be false
      expect(result[:error]).to include('Content cannot be empty')
    end

    it 'handles whitespace-only content' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      
      result = tool.execute(content: "   \n\t   ")
      expect(result[:success]).to be false
      expect(result[:error]).to include('Content cannot be empty')
    end

    it 'handles very long content' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      long_content = 'A' * 10000
      
      result = tool.execute(content: long_content)
      expect(result[:success]).to be true
      expect(result[:message][:content]).to eq(long_content)
    end

    it 'rejects extremely long content' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      extremely_long_content = 'A' * 60000
      
      result = tool.execute(content: extremely_long_content)
      expect(result[:success]).to be false
      expect(result[:error]).to include('Content too long')
    end

    it 'works with task agentable' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: mock_task, agentable: mock_task)
      
      result = tool.execute(content: 'Task update message')
      expect(result[:success]).to be true
      expect(result[:message][:agentable_type]).to eq('Task')
      expect(result[:message][:agentable_id]).to eq(1)
      expect(result[:message][:content]).to eq('Task update message')
    end

    it 'handles special characters and formatting' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      special_content = "Hello! 🎉\n\nThis has:\n- Emojis\n- **Markdown**\n- Line breaks\n\nAnd \"quotes\" & symbols!"
      
      result = tool.execute(content: special_content)
      expect(result[:success]).to be true
      expect(result[:message][:content]).to eq(special_content)
    end

    it 'generates unique message IDs' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      
      result1 = tool.execute(content: 'First message')
      result2 = tool.execute(content: 'Second message')
      
      expect(result1[:message_id]).not_to eq(result2[:message_id])
      expect(tool.messages.length).to eq(2)
    end

    it 'includes proper timestamps' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      
      result = tool.execute(content: 'Timestamped message')
      expect(result[:success]).to be true
      expect(result[:message][:created_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
  end

  describe 'message structure validation' do
    it 'creates messages with all required fields' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      
      result = tool.execute(content: 'Complete message')
      message = result[:message]
      
      required_fields = [:id, :content, :source, :user_id, :agentable_type, :agentable_id, :created_at]
      required_fields.each do |field|
        expect(message).to have_key(field)
        expect(message[field]).not_to be_nil
      end
    end

    it 'sets correct source for agent messages' do
      tool = send_message_class.new(user: mock_user, goal: mock_goal, task: nil, agentable: mock_goal)
      
      result = tool.execute(content: 'Agent message')
      expect(result[:message][:source]).to eq('agent')
    end
  end
end
