# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API smoke tests', :core, type: :request do
  include AuthHelpers

  let(:user) { create(:user) }
  let(:auth_headers) { user_jwt_headers_for(user) }

  describe 'serializers' do
    it 'can serialize a goal without errors' do
      goal = create(:goal, user: user)
      expect { GoalSerializer.new(goal).serializable_hash }.not_to raise_error
    end

    it 'can serialize a note without errors' do
      goal = create(:goal, user: user)
      note = create(:note, goal: goal, user: user)
      expect { NoteSerializer.new(note).serializable_hash }.not_to raise_error
    end

    it 'can serialize an agent_task without errors' do
      goal = create(:goal, user: user)
      task = create(:agent_task, taskable: goal, user: user)
      expect { AgentTaskSerializer.new(task).serializable_hash }.not_to raise_error
    end

    it 'can serialize a thread_message without errors' do
      goal = create(:goal, user: user)
      message = create(:thread_message, agentable: goal, user: user)
      expect { ThreadMessageSerializer.new(message).serializable_hash }.not_to raise_error
    end
  end

  describe 'key endpoints' do
    it 'GET /api/goals returns 200' do
      get '/api/goals', headers: auth_headers
      expect(response.status).to eq(200)
    end

    it 'GET /api/mcp/servers returns 200' do
      get '/api/mcp/servers', headers: auth_headers
      expect(response.status).to eq(200)
    end

    it 'GET /api/mcp/servers returns iOS-decodable response' do
      get '/api/mcp/servers', headers: auth_headers
      json = JSON.parse(response.body)

      # iOS MCPServersResponse expects these top-level keys
      expect(json).to have_key('servers')
      expect(json).to have_key('local_count')
      expect(json).to have_key('remote_count')

      # Each server must have tools as array of strings (not objects)
      # iOS MCPServer.tools is [String], not [Tool]
      json['servers'].each do |server|
        next unless server['tools'].present?

        server['tools'].each do |tool|
          expect(tool).to be_a(String), "Server '#{server['name']}' has non-string tool: #{tool.class}"
        end
      end
    end
  end
end
