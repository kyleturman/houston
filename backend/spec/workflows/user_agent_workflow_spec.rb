# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'UserAgent Workflow', type: :request do
  include_context 'authenticated user'
  let(:jwt_headers) { user_jwt_headers_for(user) }
  let(:user_agent) { user.user_agent }

  describe 'POST /api/user_agent/thread/messages' do
    before do
      user_agent.add_learning("User's name is Alex Chen")
      user_agent.add_learning("User's favorite food is sushi")
    end

    context 'with mocked LLM (fast, free, deterministic)' do
      it 'accepts user message through API endpoint' do
        # Note: With orchestrator mocked, this just verifies API endpoint works
        # Full workflow verification requires orchestrator to run (see :real_llm context)
        post '/api/user_agent/thread/messages',
             params: { message: 'What is my name and favorite food?' },
             headers: jwt_headers

        expect(response).to have_http_status(:created)

        json = JSON.parse(response.body)
        expect(json['data']['attributes']['content']).to eq('What is my name and favorite food?')
        expect(json['data']['attributes']['source']).to eq('user')
      end

      it 'requires authentication' do
        post '/api/user_agent/thread/messages',
             params: { message: 'Test message' }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'validates message content' do
        post '/api/user_agent/thread/messages',
             params: { message: '' },
             headers: jwt_headers

        # API returns 400 for blank messages
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'with real LLM (slow, costly, validates AI quality)', :real_llm do
      it 'retrieves and uses user learnings' do
        skip_unless_real_llm_enabled

        test_start = Time.current

        post '/api/user_agent/thread/messages',
             params: { message: 'What is my name and what\'s my favorite food?' },
             headers: jwt_headers

        expect(response).to have_http_status(:created)

        # Wait for processing
        user_agent.reload
        agent_messages = user_agent.thread_messages.where(source: 'agent')

        expect(agent_messages.count).to be >= 1

        combined_content = agent_messages.map(&:content).join(' ').downcase
        expect(combined_content).to include('alex')
        expect(combined_content).to include('sushi')

        test_cost = LlmCost.where(user: user).where('created_at >= ?', test_start).sum(:cost)
        puts "\n💰 Test Cost: #{LlmCost.format_cost(test_cost)}"
      end
    end
  end

  describe 'GET /api/user_agent/thread/messages' do
    before do
      ThreadMessage.create!(
        user: user,
        agentable: user_agent,
        source: :user,
        content: 'Test message'
      )
    end

    context 'with mocked LLM' do
      it 'returns thread messages' do
        get '/api/user_agent/thread/messages', headers: jwt_headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']).to be_an(Array)
        expect(json['data'].length).to be > 0
      end

      it 'requires authentication' do
        get '/api/user_agent/thread/messages'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/user_agent/reset' do
    before do
      ThreadMessage.create!(
        user: user,
        agentable: user_agent,
        source: :user,
        content: 'Test message'
      )
      user_agent.update!(llm_history: [{ role: 'user', content: 'test' }])
    end

    context 'with mocked LLM' do
      it 'clears thread messages and LLM history' do
        expect(user_agent.thread_messages.count).to be > 0
        expect(user_agent.llm_history.length).to be > 0

        post '/api/user_agent/reset', headers: jwt_headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['ok']).to eq(true)

        user_agent.reload
        expect(user_agent.thread_messages.count).to eq(0)
        expect(user_agent.llm_history.length).to eq(0)
      end

      it 'requires authentication' do
        post '/api/user_agent/reset'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
