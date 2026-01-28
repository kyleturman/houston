# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Goal Creation Workflow', type: :request do
  include_context 'authenticated user'
  let(:jwt_headers) { user_jwt_headers_for(user) }

  describe 'POST /api/goal_creation_chat/message' do
    context 'with mocked LLM (fast, free, deterministic)' do
      context 'initial message' do
        it 'processes first message through API' do
          # Note: The default mocks already provide a stubbed response
          # We just need to verify the API endpoint works correctly
          post '/api/goal_creation_chat/message',
               params: {
                 message: 'Learn piano',
                 conversation_history: []
               },
               headers: jwt_headers

          expect(response).to have_http_status(:success)

          json = JSON.parse(response.body)
          # With default mocks, reply will be "stubbed response"
          expect(json).to have_key('reply')
          expect(json['ready_to_create']).to eq(false)
          expect(json['goal_data']).to be_nil
        end

        it 'requires authentication' do
          post '/api/goal_creation_chat/message',
               params: { message: 'Learn piano' }

          expect(response).to have_http_status(:unauthorized)
        end

        it 'validates message presence' do
          post '/api/goal_creation_chat/message',
               params: { message: '' },
               headers: jwt_headers

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json['error']).to include('blank')
        end
      end

      context 'ready to create goal' do
        before do
          # Mock LLM to call finalize_goal_creation tool
          mock_llm_service_response(
            mock_goal_creation_response(
              title: 'Learn Piano',
              description: 'Learn to play piano for fun',
              agent_instructions: 'Help user find beginner piano resources and practice routines',
              learnings: ['User is a complete beginner', 'Has 30 minutes daily for practice']
            )
          )
        end

        it 'returns goal data when ready to create' do
          post '/api/goal_creation_chat/message',
               params: {
                 message: 'Yes, let\'s create the goal',
                 conversation_history: [
                   { role: 'user', content: 'I want to learn piano' },
                   { role: 'assistant', content: 'Tell me more...' }
                 ]
               },
               headers: jwt_headers

          expect(response).to have_http_status(:success)

          json = JSON.parse(response.body)
          expect(json['ready_to_create']).to eq(true)
          expect(json['goal_data']).to be_present
          expect(json['goal_data']['title']).to eq('Learn Piano')
          expect(json['goal_data']['description']).to be_present
          expect(json['goal_data']['agent_instructions']).to be_present
          expect(json['goal_data']['learnings']).to be_an(Array)
        end
      end
    end

    context 'with real LLM (slow, costly, validates AI quality)', :real_llm do
      it 'completes full conversation and extracts goal data' do
        skip_unless_real_llm_enabled

        test_start = Time.current
        conversation_history = []

        # Multi-turn conversation: provide info, then confirm creation
        # Different LLMs may need different numbers of turns
        messages = [
          'I want to get fit and healthy. I work long hours and have limited time.',
          'I can do 30 minutes 3 times a week. I prefer home workouts.',
          "Yes, that sounds perfect. Let's create the goal.",
          "I've given you everything you need. Please create the goal now.",
          "Please go ahead and create the goal with what you have."
        ]

        ready = false
        last_json = nil
        messages.each_with_index do |msg, i|
          post '/api/goal_creation_chat/message',
               params: {
                 message: msg,
                 conversation_history: conversation_history
               },
               headers: jwt_headers

          expect(response).to have_http_status(:success)
          last_json = JSON.parse(response.body)

          if last_json['ready_to_create']
            ready = true
            break
          end

          conversation_history << { role: 'user', content: msg }
          reply_text = last_json['reply'].presence || 'I understand. Tell me more.'
          conversation_history << { role: 'assistant', content: reply_text }
        end

        expect(ready).to eq(true), "LLM did not finalize goal after #{messages.length} turns"
        expect(last_json['goal_data']).to be_present

        # Validate goal data
        goal_data = last_json['goal_data']
        expect(goal_data['title']).to be_present
        expect(goal_data['description']).to be_present
        expect(goal_data['agent_instructions']).to be_present
        expect(goal_data['learnings']).to be_an(Array)
        expect(goal_data['learnings'].length).to be >= 1

        # Validate content quality
        expect(goal_data['title'].length).to be_between(3, 100)
        expect(goal_data['description'].length).to be_between(20, 500)

        test_cost = LlmCost.where(user: user).where('created_at >= ?', test_start).sum(:cost)
        puts "\n💰 Test Cost: #{LlmCost.format_cost(test_cost)}"
      end

      it 'does not create goal immediately on brief first message' do
        skip_unless_real_llm_enabled

        test_start = Time.current

        post '/api/goal_creation_chat/message',
             params: {
               message: 'Learn piano',
               conversation_history: []
             },
             headers: jwt_headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        # Should ask follow-up questions, not create immediately
        expect(json['ready_to_create']).to eq(false)
        # Reply should contain a question (some providers may return empty reply text)
        expect(json['reply']).to include('?') if json['reply'].present?

        test_cost = LlmCost.where(user: user).where('created_at >= ?', test_start).sum(:cost)
        puts "\n💰 Test Cost: #{LlmCost.format_cost(test_cost)}"
      end
    end
  end

  describe 'POST /api/goals (creating goal from chat data)' do
    let(:goal_data) do
      {
        title: 'Learn Piano',
        description: 'Learn to play piano for fun and relaxation',
        agent_instructions: 'Help find beginner resources and practice routines',
        learnings: ['User is a complete beginner', 'Has 30 minutes daily']
      }
    end

    context 'with mocked LLM' do
      it 'creates goal from extracted data' do
        initial_count = Goal.count

        post '/api/goals',
             params: { goal: goal_data },
             headers: jwt_headers

        expect(response).to have_http_status(:created)

        json = JSON.parse(response.body)
        expect(json['data']['attributes']['title']).to eq('Learn Piano')
        expect(json['data']['attributes']['status']).to eq('working')

        expect(Goal.count).to eq(initial_count + 1)
        goal = Goal.last
        expect(goal.title).to eq('Learn Piano')
        expect(goal.agent_instructions).to be_present
      end

      it 'requires authentication' do
        post '/api/goals',
             params: { goal: goal_data }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'validates required fields' do
        post '/api/goals',
             params: { goal: { title: '' } },
             headers: jwt_headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
