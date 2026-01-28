# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API::Updates', type: :request do
  let(:user) { create(:user) }
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

  describe 'GET /api/updates/since/:timestamp' do
    let(:base_time) { Time.parse('2025-11-04T12:00:00Z') }
    let!(:old_task) { create(:agent_task, user: user, title: 'Old Task', updated_at: base_time - 1.hour) }
    let!(:new_task) { create(:agent_task, user: user, title: 'New Task', updated_at: base_time + 1.hour, status: 'completed') }
    let!(:old_note) { create(:note, user: user, content: 'Old Note', updated_at: base_time - 1.hour) }
    let!(:new_note) { create(:note, user: user, content: 'New Note', updated_at: base_time + 1.hour) }
    let!(:old_goal) { create(:goal, user: user, title: 'Old Goal', updated_at: base_time - 1.hour) }
    let!(:new_goal) { create(:goal, user: user, title: 'New Goal', updated_at: base_time + 1.hour) }

    it 'requires authentication' do
      # Remove the mock for this specific test
      allow_any_instance_of(Api::BaseController).to receive(:authenticate_user!).and_call_original
      allow_any_instance_of(Api::BaseController).to receive(:current_user).and_call_original

      get "/api/updates/since/#{base_time.iso8601}"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns updates since given timestamp' do
      get "/api/updates/since/#{base_time.iso8601}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:tasks].length).to eq(1)
      expect(json_response[:tasks].first[:attributes][:title]).to eq('New Task')
      expect(json_response[:notes].length).to eq(1)
      expect(json_response[:notes].first[:attributes][:content]).to eq('New Note')
      expect(json_response[:goals].length).to eq(1)
      expect(json_response[:goals].first[:attributes][:title]).to eq('New Goal')
    end

    it 'returns empty arrays when no updates' do
      future_time = base_time + 2.hours
      get "/api/updates/since/#{future_time.iso8601}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:tasks]).to eq([])
      expect(json_response[:notes]).to eq([])
      expect(json_response[:goals]).to eq([])
    end

    it 'includes current timestamp in response' do
      get "/api/updates/since/#{base_time.iso8601}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:timestamp]).to be_present
      expect { Time.parse(json_response[:timestamp]) }.not_to raise_error
    end

    it 'serializes tasks with correct structure' do
      get "/api/updates/since/#{base_time.iso8601}", headers: headers

      expect(response).to have_http_status(:ok)
      task = json_response[:tasks].first
      expect(task[:id]).to be_present
      expect(task[:type]).to eq('agent_task')
      expect(task[:attributes]).to include(:title, :status, :priority, :created_at, :updated_at)
    end

    it 'serializes notes with correct structure' do
      get "/api/updates/since/#{base_time.iso8601}", headers: headers

      expect(response).to have_http_status(:ok)
      note = json_response[:notes].first
      expect(note[:id]).to be_present
      expect(note[:type]).to eq('note')
      expect(note[:attributes]).to include(:content, :source, :created_at, :updated_at)
    end

    it 'serializes goals with correct structure' do
      get "/api/updates/since/#{base_time.iso8601}", headers: headers

      expect(response).to have_http_status(:ok)
      goal = json_response[:goals].first
      expect(goal[:id]).to be_present
      expect(goal[:type]).to eq('goal')
      expect(goal[:attributes]).to include(:title, :status, :created_at, :updated_at)
    end

    it 'includes goal_id and goal_title for tasks' do
      goal = create(:goal, user: user, title: 'Test Goal')
      task = create(:agent_task, user: user, goal: goal, title: 'Task with Goal', updated_at: base_time + 1.hour)

      get "/api/updates/since/#{base_time.iso8601}", headers: headers

      expect(response).to have_http_status(:ok)
      task_data = json_response[:tasks].find { |t| t[:id] == task.id.to_s }
      expect(task_data[:attributes][:goal_id]).to eq(goal.id.to_s)
      expect(task_data[:attributes][:goal_title]).to eq('Test Goal')
    end

    it 'returns error when timestamp is missing' do
      get '/api/updates/since/', headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns error when timestamp format is invalid' do
      get '/api/updates/since/invalid-timestamp', headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response[:error]).to include('Invalid timestamp format')
    end

    it 'accepts ISO8601 timestamp with fractional seconds' do
      timestamp = base_time.iso8601(3) # Include milliseconds
      get "/api/updates/since/#{timestamp}", headers: headers

      expect(response).to have_http_status(:ok)
    end

    it 'limits results to 50 items per resource type' do
      # Create 60 tasks updated after base_time
      60.times do |i|
        create(:agent_task, user: user, title: "Task #{i}", updated_at: base_time + (i + 1).minutes)
      end

      get "/api/updates/since/#{base_time.iso8601}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:tasks].length).to eq(50)
    end

    it 'only returns resources for authenticated user' do
      other_user = create(:user)
      other_task = create(:agent_task, user: other_user, title: 'Other User Task', updated_at: base_time + 1.hour)

      get "/api/updates/since/#{base_time.iso8601}", headers: headers

      expect(response).to have_http_status(:ok)
      task_ids = json_response[:tasks].map { |t| t[:id] }
      expect(task_ids).not_to include(other_task.id.to_s)
    end

    context 'with very old timestamp' do
      it 'returns recent updates within limit' do
        very_old_time = Time.parse('2020-01-01T00:00:00Z')
        get "/api/updates/since/#{very_old_time.iso8601}", headers: headers

        expect(response).to have_http_status(:ok)
        # Should return tasks, notes, goals within 50 item limit each
        expect(json_response[:tasks].length).to be <= 50
        expect(json_response[:notes].length).to be <= 50
        expect(json_response[:goals].length).to be <= 50
      end
    end

    context 'with future timestamp' do
      it 'returns empty results' do
        future_time = Time.now + 1.year
        get "/api/updates/since/#{future_time.iso8601}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json_response[:tasks]).to eq([])
        expect(json_response[:notes]).to eq([])
        expect(json_response[:goals]).to eq([])
      end
    end
  end

  private

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end
end
