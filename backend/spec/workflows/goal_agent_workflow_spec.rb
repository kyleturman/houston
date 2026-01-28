# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Goal Agent Workflow', type: :request do
  include_context 'authenticated user with goal'
  let(:jwt_headers) { user_jwt_headers_for(user) }

  describe 'POST /api/goals/:id/thread/messages' do
    before do
      goal.update!(status: :working)
    end

    context 'with mocked LLM (fast, free, deterministic)' do
      it 'accepts user message through API endpoint' do
        # Note: With orchestrator mocked, this just verifies API endpoint works
        # Full workflow verification requires orchestrator to run (see :real_llm context)
        post "/api/goals/#{goal.id}/thread/messages",
             params: { message: 'What is the title of this goal?' },
             headers: jwt_headers

        expect(response).to have_http_status(:created)

        json = JSON.parse(response.body)
        expect(json['data']['attributes']['content']).to eq('What is the title of this goal?')
        expect(json['data']['attributes']['source']).to eq('user')
      end

      it 'requires authentication' do
        post "/api/goals/#{goal.id}/thread/messages",
             params: { message: 'Test message' }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'validates message content' do
        post "/api/goals/#{goal.id}/thread/messages",
             params: { message: '' },
             headers: jwt_headers

        # API returns 400 for blank messages (ActionController::ParameterMissing)
        expect(response).to have_http_status(:bad_request)
      end

      it 'rejects messages for archived goals' do
        goal.update!(status: :archived)

        post "/api/goals/#{goal.id}/thread/messages",
             params: { message: 'Test message' },
             headers: jwt_headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with real LLM (slow, costly, validates AI quality)', :real_llm do
      it 'responds to user questions about goal' do
        skip_unless_real_llm_enabled

        goal.update!(title: 'Learn Piano', description: 'Learn to play piano for fun')
        test_start = Time.current

        post "/api/goals/#{goal.id}/thread/messages",
             params: { message: 'What is the title of this goal?' },
             headers: jwt_headers

        expect(response).to have_http_status(:created)

        # Wait for processing
        goal.reload
        agent_messages = goal.thread_messages.where(source: 'agent')

        expect(agent_messages.count).to be > 0
        response_text = agent_messages.first.content.downcase
        expect(response_text).to include('piano')

        # Calculate cost
        test_cost = LlmCost.where(user: user).where('created_at >= ?', test_start).sum(:cost)
        puts "\n💰 Test Cost: #{LlmCost.format_cost(test_cost)}"
      end
    end

    describe 'task creation from user request' do
      before do
        goal.update!(
          title: 'Improve Fitness',
          description: 'Get in better shape',
          status: :working
        )
      end

      context 'with mocked LLM' do
        it 'accepts task creation request through API endpoint' do
          # Note: With orchestrator mocked, this just verifies the API endpoint works
          # Full workflow verification requires orchestrator to run (see :real_llm context)
          post "/api/goals/#{goal.id}/thread/messages",
               params: { message: 'Create a task to research home workouts' },
               headers: jwt_headers

          expect(response).to have_http_status(:created)

          json = JSON.parse(response.body)
          expect(json['data']['attributes']['content']).to eq('Create a task to research home workouts')
          expect(json['data']['attributes']['source']).to eq('user')
        end
      end

      context 'with real LLM', :real_llm do
        it 'creates task from user request and validates iOS message format' do
          skip_unless_real_llm_enabled

          test_start = Time.current

          post "/api/goals/#{goal.id}/thread/messages",
               params: { message: 'Create a task to research effective 20-minute home workouts' },
               headers: jwt_headers

          expect(response).to have_http_status(:created)

          goal.reload
          task = goal.agent_tasks.last

          expect(task).to be_present
          expect(task.title).to be_present
          expect(task.instructions).to be_present

          # Validate iOS message format
          puts "\n📱 Validating iOS message format..."

          # Fetch messages via API (like iOS does)
          get "/api/goals/#{goal.id}/thread/messages", headers: jwt_headers
          expect(response).to have_http_status(:ok)

          json = JSON.parse(response.body)
          messages = json['data']

          # Find tool messages (create_task)
          tool_messages = messages.select do |msg|
            msg.dig('attributes', 'metadata', 'tool_activity', 'name') == 'create_task'
          end

          expect(tool_messages).not_to be_empty, "No create_task tool messages found in API response"

          tool_message = tool_messages.first
          attrs = tool_message['attributes']
          tool_activity = attrs['metadata']['tool_activity']

          puts "   ✅ Found create_task tool message (ID: #{tool_message['id']})"

          # Validate structure that iOS expects
          expect(attrs['source']).to eq('agent'), "Tool message should have source=agent"
          puts "      source: #{attrs['source']} ✓"

          expect(attrs['content']).to be_present, "Tool message should have content"
          puts "      content: #{attrs['content']} ✓"

          expect(attrs['metadata']).to be_present, "Tool message should have metadata"
          expect(tool_activity).to be_present, "Metadata should contain tool_activity"
          puts "      metadata.tool_activity: present ✓"

          # Validate tool_activity structure
          expect(tool_activity['id']).to be_present, "tool_activity should have id"
          puts "      tool_activity.id: #{tool_activity['id']} ✓"

          expect(tool_activity['name']).to eq('create_task'), "tool_activity.name should be create_task"
          puts "      tool_activity.name: #{tool_activity['name']} ✓"

          expect(tool_activity['status']).to be_in(['in_progress', 'success']), "tool_activity should have valid status"
          puts "      tool_activity.status: #{tool_activity['status']} ✓"

          # Input is optional (may not be present in in_progress state)
          if tool_activity['input'].present?
            puts "      tool_activity.input: #{tool_activity['input'].keys.join(', ')} ✓"
          else
            puts "      tool_activity.input: (not yet populated) ⚠️"
          end

          # If status is success, should have data
          if tool_activity['status'] == 'success'
            expect(tool_activity['data']).to be_present, "Successful tool should have data"
            expect(tool_activity['data']['task_id']).to be_present, "Data should include task_id"
            puts "      tool_activity.data.task_id: #{tool_activity['data']['task_id']} ✓"
          end

          puts "\n   ✅ Tool message format valid for iOS rendering"

          # Verify different message types are present
          user_messages = messages.select { |m| m['attributes']['source'] == 'user' }
          agent_messages = messages.select { |m| m['attributes']['source'] == 'agent' }

          expect(user_messages).not_to be_empty, "Should have user messages"
          # Agent messages are optional (agent may just create task without text response)

          puts "   ✅ Message mix: #{user_messages.count} user, #{agent_messages.count} agent, #{tool_messages.count} tool"

          test_cost = LlmCost.where(user: user).where('created_at >= ?', test_start).sum(:cost)
          puts "\n💰 Test Cost: #{LlmCost.format_cost(test_cost)}"
        end
      end
    end
  end
end
