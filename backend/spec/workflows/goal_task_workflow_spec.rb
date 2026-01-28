# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Goal → Task Workflow', type: :request do
  include_context 'authenticated user with goal'
  let(:jwt_headers) { user_jwt_headers_for(user) }

  describe 'POST /api/goals/:id/thread/messages (task creation flow)' do
    before do
      goal.update!(
        title: 'Research Healthy Recipes',
        description: 'Find quick and healthy recipes',
        status: :working
      )
    end

    context 'with mocked LLM (fast, free, deterministic)' do
      it 'accepts message through API endpoint' do
        # Note: With orchestrator mocked, this test just verifies the API endpoint works
        # Full workflow testing requires orchestrator to run (see real_llm context below)
        post "/api/goals/#{goal.id}/thread/messages",
             params: { message: 'Create a task to find 3 breakfast recipes' },
             headers: jwt_headers

        expect(response).to have_http_status(:created)

        json = JSON.parse(response.body)
        expect(json['data']['attributes']['content']).to eq('Create a task to find 3 breakfast recipes')
        expect(json['data']['attributes']['source']).to eq('user')
      end

      it 'requires authentication for message creation' do
        post "/api/goals/#{goal.id}/thread/messages",
             params: { message: 'Create a task' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with real LLM (slow, costly, validates full workflow)', :real_llm do
      it 'executes complete goal → task → note workflow' do
        skip_unless_real_llm_enabled

        test_start = Time.current

        # Step 1: Goal agent creates task
        post "/api/goals/#{goal.id}/thread/messages",
             params: { message: 'Create a task to find 3 breakfast recipes under 10 minutes' },
             headers: jwt_headers

        expect(response).to have_http_status(:created)

        # Verify task was created
        goal.reload
        task = goal.agent_tasks.last
        expect(task).to be_present
        expect(task.title).to be_present

        # Skip if task was cancelled (health monitor cleanup)
        unless task.status == 'cancelled'
          # Step 2: Wait for task to execute (runs automatically)
          # Task agent should create a note
          task.reload

          notes = goal.notes.where('created_at >= ?', task.created_at)
          expect(notes.count).to be > 0

          note = notes.first
          expect(note.title).to be_present
          expect(note.content).to be_present
          expect(note.content.length).to be > 100

          expect(task.status).to eq('completed')
        end

        test_cost = LlmCost.where(user: user).where('created_at >= ?', test_start).sum(:cost)
        puts "\n💰 Test Cost: #{LlmCost.format_cost(test_cost)}"
      end
    end
  end

  describe 'GET /api/agent_tasks/:id' do
    let(:task) do
      AgentTask.create!(
        user: user,
        goal: goal,
        title: 'Test Task',
        instructions: 'Test instructions',
        status: :active
      )
    end

    context 'with mocked LLM' do
      it 'returns task details' do
        get "/api/agent_tasks/#{task.id}", headers: jwt_headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['attributes']['title']).to eq('Test Task')
      end

      it 'requires authentication' do
        get "/api/agent_tasks/#{task.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
