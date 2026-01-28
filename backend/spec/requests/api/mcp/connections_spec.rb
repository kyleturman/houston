# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Mcp::Connections', type: :request do
  let(:user) { create(:user) }
  let(:auth_headers) { user_jwt_headers_for(user) }

  let!(:plaid_server) do
    McpServer.find_or_create_by!(name: 'plaid') do |server|
      server.metadata = {
        'auth_provider' => '../mcp/auth-providers/plaid.json',
        'connection_strategy' => 'multiple'
      }
    end
  end

  before do
    # Prevent cleanup from removing test servers
    allow(Mcp::ConnectionManager.instance).to receive(:cleanup_stale_servers!)
  end

  describe 'GET /api/mcp/:server_name/connections' do
    context 'when user has no connections' do
      it 'returns empty array' do
        get "/api/mcp/plaid/connections", headers: auth_headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['connections']).to eq([])
      end
    end

    context 'when user has active connections' do
      let!(:connection1) do
        create(:user_mcp_connection,
          user: user,
          mcp_server: plaid_server,
          connection_identifier: 'item-bank1',
          status: :active,
          metadata: {
            'institution_name' => 'Chase',
            'institution_id' => 'ins_1'
          }
        )
      end

      let!(:connection2) do
        create(:user_mcp_connection,
          user: user,
          mcp_server: plaid_server,
          connection_identifier: 'item-bank2',
          status: :active,
          metadata: {
            'institution_name' => 'Bank of America',
            'institution_id' => 'ins_2'
          }
        )
      end

      let!(:disconnected_connection) do
        create(:user_mcp_connection,
          user: user,
          mcp_server: plaid_server,
          status: :disconnected
        )
      end

      it 'returns only active connections' do
        get "/api/mcp/plaid/connections", headers: auth_headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['connections'].size).to eq(2)

        connection_ids = json['connections'].map { |c| c['id'] }
        expect(connection_ids).to contain_exactly(connection1.id, connection2.id)
      end

      it 'serializes connection details correctly' do
        get "/api/mcp/plaid/connections", headers: auth_headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        first_connection = json['connections'].first

        expect(first_connection).to include(
          'id',
          'serverName',
          'label',
          'institutionName',
          'accountCount',
          'status',
          'metadata',
          'createdAt'
        )
      end
    end
  end

  describe 'GET /api/mcp/:server_name/status' do
    it 'returns connection status' do
      get "/api/mcp/plaid/status", headers: auth_headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json).to include('connected', 'connection_count', 'connections')
    end

    context 'with active connections' do
      let!(:connection) do
        create(:user_mcp_connection,
          user: user,
          mcp_server: plaid_server,
          status: :active
        )
      end

      it 'shows connected status' do
        get "/api/mcp/plaid/status", headers: auth_headers

        json = JSON.parse(response.body)
        expect(json['connected']).to be true
        expect(json['connection_count']).to eq(1)
      end
    end
  end

  describe 'DELETE /api/mcp/connections/:id' do
    let!(:connection) do
      create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        status: :active
      )
    end

    context 'when connection belongs to user' do
      it 'disconnects the connection' do
        delete "/api/mcp/connections/#{connection.id}", headers: auth_headers

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['message']).to eq('Connection disconnected')

        connection.reload
        expect(connection.status).to eq('disconnected')
      end
    end

    context 'when connection does not exist' do
      it 'returns 404' do
        delete "/api/mcp/connections/99999", headers: auth_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Connection not found')
      end
    end

    context 'when connection belongs to another user' do
      let(:other_user) { create(:user) }
      let!(:other_connection) do
        create(:user_mcp_connection,
          user: other_user,
          mcp_server: plaid_server,
          status: :active
        )
      end

      it 'returns 404' do
        delete "/api/mcp/connections/#{other_connection.id}", headers: auth_headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
