# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Agent Histories API', type: :request do
  include_context 'authenticated user with goal'

  let(:auth_token_headers) { user_jwt_headers_for(user) }

  # Helper to create enough thread messages to satisfy archiving threshold
  def create_thread_messages_for_archive(agentable, count: 12)
    count.times do |i|
      ThreadMessage.create!(
        agentable: agentable,
        user: agentable.respond_to?(:user) ? agentable.user : user,
        source: :user,
        content: "Message #{i}"
      )
    end
  end

  describe 'GET /api/goals/:goal_id/agent_histories' do
    before do
      # Create some archived sessions
      3.times do |i|
        goal.agent_histories.create!(
          agent_history: [{ role: 'user', content: "Question #{i}" }],
          summary: "User asked about topic #{i}",
          message_count: 1,
          token_count: 100,
          completed_at: i.days.ago
        )
      end
    end

    it 'returns agent histories for the goal' do
      get "/api/goals/#{goal.id}/agent_histories",
          headers: auth_token_headers,
          as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json['data']).to be_an(Array)
      expect(json['data'].length).to eq(3)

      # Verify JSONAPI structure
      json['data'].each do |history|
        expect(history['type']).to eq('agent_history')
        expect(history['attributes']).to include(
          'summary', 'completion_reason', 'message_count', 'token_count',
          'agentable_type', 'agentable_id', 'started_at', 'completed_at'
        )
      end
    end
  end

  describe 'GET /api/goals/:goal_id/agent_histories/:id' do
    let!(:history) do
      goal.agent_histories.create!(
        agent_history: [{ role: 'user', content: 'Test question' }],
        summary: 'User asked about test',
        message_count: 5,
        token_count: 200,
        completed_at: 1.hour.ago,
        started_at: 2.hours.ago
      )
    end

    let!(:thread_messages) do
      5.times.map do |i|
        ThreadMessage.create!(
          agentable: goal,
          user: user,
          source: :user,
          content: "Message #{i}",
          agent_history: history
        )
      end
    end

    it 'returns the agent history with thread messages' do
      get "/api/goals/#{goal.id}/agent_histories/#{history.id}",
          headers: auth_token_headers,
          as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json['data']['type']).to eq('agent_history')
      expect(json['data']['attributes']['summary']).to eq('User asked about test')

      # Verify included thread messages
      expect(json['included']).to be_present
      expect(json['included']['thread_messages']).to be_an(Array)
      expect(json['included']['thread_messages'].length).to eq(5)
    end
  end

  describe 'DELETE /api/goals/:goal_id/agent_histories/:id' do
    let!(:history) do
      goal.agent_histories.create!(
        agent_history: [{ role: 'user', content: 'Test question' }],
        summary: 'User asked about test',
        message_count: 1,
        token_count: 100,
        completed_at: 1.hour.ago,
        started_at: 2.hours.ago
      )
    end

    let!(:thread_messages) do
      3.times.map do |i|
        ThreadMessage.create!(
          agentable: goal,
          user: user,
          source: :user,
          content: "Message #{i}",
          agent_history: history
        )
      end
    end

    it 'deletes the agent history and its thread messages' do
      expect {
        delete "/api/goals/#{goal.id}/agent_histories/#{history.id}",
               headers: auth_token_headers,
               as: :json
      }.to change(AgentHistory, :count).by(-1)
        .and change(ThreadMessage, :count).by(-3)

      expect(response).to have_http_status(:no_content)
    end

    context 'with tasks created during the session' do
      let!(:completed_task) do
        AgentTask.create!(
          goal: goal,
          user: user,
          title: 'Completed task during session',
          status: :completed,
          result_summary: 'Task was completed successfully',
          created_at: history.started_at + 30.minutes # During session
        )
      end

      let!(:incomplete_task) do
        AgentTask.create!(
          goal: goal,
          user: user,
          title: 'Incomplete task during session',
          status: :active,
          result_summary: 'Partial progress made',
          created_at: history.started_at + 45.minutes # During session
        )
      end

      let!(:task_outside_session) do
        AgentTask.create!(
          goal: goal,
          user: user,
          title: 'Task outside session',
          status: :completed,
          result_summary: 'This should not be touched',
          created_at: history.completed_at + 1.hour # After session
        )
      end

      it 'deletes completed tasks and clears summary on incomplete tasks' do
        expect {
          delete "/api/goals/#{goal.id}/agent_histories/#{history.id}",
                 headers: auth_token_headers,
                 as: :json
        }.to change(AgentTask, :count).by(-1) # Only completed task deleted

        expect(response).to have_http_status(:no_content)

        # Completed task during session should be deleted
        expect(AgentTask.exists?(completed_task.id)).to be false

        # Incomplete task during session should still exist but have result_summary cleared
        incomplete_task.reload
        expect(incomplete_task.result_summary).to be_nil
        expect(incomplete_task.title).to eq('Incomplete task during session')

        # Task outside session should be untouched
        task_outside_session.reload
        expect(task_outside_session.result_summary).to eq('This should not be touched')
      end
    end
  end

  describe 'GET /api/goals/:goal_id/agent_histories/current' do
    context 'with an active session' do
      before do
        goal.start_agent_turn_if_needed!
        goal.add_to_llm_history({ role: 'user', content: 'Current question' })

        # Create some current session thread messages
        3.times do |i|
          ThreadMessage.create!(
            agentable: goal,
            user: user,
            source: :user,
            content: "Current message #{i}",
            agent_history: nil # Current session has nil agent_history_id
          )
        end
      end

      it 'returns the current session info' do
        get "/api/goals/#{goal.id}/agent_histories/current",
            headers: auth_token_headers,
            as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['data']['id']).to eq('current')
        expect(json['data']['type']).to eq('agent_history')
        expect(json['data']['attributes']['is_current']).to eq(true)
        expect(json['data']['attributes']['message_count']).to eq(3)
        expect(json['data']['attributes']['completed_at']).to be_nil

        # Verify included thread messages
        expect(json['included']['thread_messages']).to be_an(Array)
        expect(json['included']['thread_messages'].length).to eq(3)
      end
    end

    context 'with no active session' do
      it 'returns current session with zero messages' do
        get "/api/goals/#{goal.id}/agent_histories/current",
            headers: auth_token_headers,
            as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['data']['attributes']['message_count']).to eq(0)
        expect(json['included']['thread_messages']).to eq([])
      end
    end
  end

  describe 'DELETE /api/goals/:goal_id/agent_histories/current' do
    before do
      goal.start_agent_turn_if_needed!
      goal.add_to_llm_history({ role: 'user', content: 'Message 1' })
      goal.add_to_llm_history({ role: 'assistant', content: 'Response 1' })

      # Create current session thread messages
      5.times do |i|
        ThreadMessage.create!(
          agentable: goal,
          user: user,
          source: :user,
          content: "Current message #{i}",
          agent_history: nil
        )
      end
    end

    it 'resets the current session without archiving' do
      expect(goal.reload.llm_history.length).to eq(2)
      expect(goal.thread_messages.current_session.count).to eq(5)

      delete "/api/goals/#{goal.id}/agent_histories/current",
             headers: auth_token_headers,
             as: :json

      expect(response).to have_http_status(:no_content)

      goal.reload
      expect(goal.llm_history).to be_empty
      expect(goal.thread_messages.current_session.count).to eq(0)
      expect(goal.runtime_state&.dig('current_turn_started_at')).to be_nil

      # Should NOT have created an agent history (not archived, just discarded)
      expect(goal.agent_histories.count).to eq(0)
    end
  end

  describe 'User Agent endpoints' do
    let(:user_agent) { user.user_agent }

    describe 'GET /api/user_agent/agent_histories' do
      before do
        2.times do |i|
          user_agent.agent_histories.create!(
            agent_history: [{ role: 'user', content: "Question #{i}" }],
            summary: "User agent topic #{i}",
            message_count: 1,
            token_count: 100,
            completed_at: i.days.ago
          )
        end
      end

      it 'returns agent histories for the user agent' do
        get '/api/user_agent/agent_histories',
            headers: auth_token_headers,
            as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['data']).to be_an(Array)
        expect(json['data'].length).to eq(2)
      end
    end

    describe 'DELETE /api/user_agent/agent_histories/current' do
      before do
        user_agent.start_agent_turn_if_needed!
        user_agent.add_to_llm_history({ role: 'user', content: 'Test' })

        3.times do |i|
          ThreadMessage.create!(
            agentable: user_agent,
            user: user,
            source: :user,
            content: "Message #{i}",
            agent_history: nil
          )
        end
      end

      it 'resets the user agent current session' do
        delete '/api/user_agent/agent_histories/current',
               headers: auth_token_headers,
               as: :json

        expect(response).to have_http_status(:no_content)

        user_agent.reload
        expect(user_agent.llm_history).to be_empty
        expect(user_agent.thread_messages.current_session.count).to eq(0)
      end
    end
  end
end
