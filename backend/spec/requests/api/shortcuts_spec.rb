# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API::Shortcuts', type: :request do
  let(:user) { create(:user) }
  let(:device) { create(:device, user: user) }
  let(:user_token) { 'test_user_token' }
  let(:headers) { { 'Authorization' => "User #{user_token}" } }

  before do
    # Mock user authentication
    allow_any_instance_of(Api::BaseController).to receive(:authenticate_user!) do
      controller = Api::BaseController.new
      controller.instance_variable_set(:@current_user, user)
    end
    allow_any_instance_of(Api::BaseController).to receive(:current_user).and_return(user)
  end

  describe 'POST /api/shortcuts/agent_query' do
    let(:goal) { create(:goal, user: user, title: 'Test Goal') }

    it 'creates agent task and queues orchestrator job' do
      expect(Agents::Orchestrator).to receive(:perform_async).with('AgentTask', kind_of(Integer))

      post '/api/shortcuts/agent_query',
           params: { query: 'What tasks do I have today?', goal_id: goal.id },
           headers: headers

      expect(response).to have_http_status(:accepted)
      expect(json_response[:success]).to be true
      expect(json_response[:task_id]).to be_present

      task = AgentTask.find(json_response[:task_id])
      expect(task.user).to eq(user)
      expect(task.goal).to eq(goal)
      expect(task.title).to eq('What tasks do I have today?')
      expect(task.status).to eq('active')
    end

    it 'works without goal specified' do
      expect(Agents::Orchestrator).to receive(:perform_async)

      post '/api/shortcuts/agent_query',
           params: { query: 'General query' },
           headers: headers

      expect(response).to have_http_status(:accepted)
      expect(json_response[:goal_id]).to be_nil
    end

    it 'returns error for missing query' do
      post '/api/shortcuts/agent_query', headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response[:error]).to include('query')
    end

    it 'returns error for invalid goal' do
      post '/api/shortcuts/agent_query',
           params: { query: 'Test', goal_id: 99999 },
           headers: headers

      expect(response).to have_http_status(:not_found)
      expect(json_response[:error]).to include('Goal not found')
    end

    it 'requires user authentication' do
      # Clear the mock for this test only
      allow_any_instance_of(Api::BaseController).to receive(:authenticate_user!).and_call_original
      allow_any_instance_of(Api::BaseController).to receive(:current_user).and_call_original

      post '/api/shortcuts/agent_query',
           params: { query: 'Test' }
           # No headers provided

      expect(response).to have_http_status(:unauthorized)
    end
  end

  private

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end
end
