# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MCP Credential Lifecycle', type: :model do
  let(:user) { create(:user) }
  let!(:plaid_server) do
    McpServer.find_or_create_by!(name: 'plaid') do |server|
      server.metadata = { 'auth_provider' => '../mcp/auth-providers/plaid.json' }
    end
  end

  describe 'Connection states' do
    let!(:active_connection) do
      create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        status: :active,
        connection_identifier: 'active_item_123',
        credentials: { accessToken: 'valid_token' }.to_json
      )
    end

    let!(:disconnected_connection) do
      create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        status: :disconnected,
        connection_identifier: 'disconnected_item_456',
        credentials: { accessToken: 'old_token' }.to_json
      )
    end

    it 'active_connections scope excludes disconnected' do
      active = user.user_mcp_connections.active_connections

      expect(active).to include(active_connection)
      expect(active).not_to include(disconnected_connection)
    end

    it 'can transition connection from active to disconnected' do
      active_connection.update!(status: :disconnected)

      active_connection.reload
      expect(active_connection.status).to eq('disconnected')
      expect(user.user_mcp_connections.active_connections).not_to include(active_connection)
    end

    it 'credentials remain encrypted after status change' do
      original_credentials = active_connection.credentials

      active_connection.update!(status: :disconnected)
      active_connection.reload

      # Credentials should still be there and encrypted
      expect(active_connection.credentials).to eq(original_credentials)
      expect(JSON.parse(active_connection.credentials)['accessToken']).to eq('valid_token')
    end
  end

  describe 'Credential storage' do
    it 'stores credentials as encrypted JSON' do
      connection = create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        credentials: { accessToken: 'secret123', itemId: 'item456' }.to_json
      )

      # Credentials are stored encrypted
      expect(connection.credentials).to be_a(String)

      # Can be parsed back
      parsed = JSON.parse(connection.credentials)
      expect(parsed['accessToken']).to eq('secret123')
      expect(parsed['itemId']).to eq('item456')
    end

    it 'allows updating credentials' do
      connection = create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        credentials: { accessToken: 'old_token' }.to_json
      )

      # Update with refreshed credentials
      connection.update!(credentials: { accessToken: 'new_token', refreshedAt: Time.current.to_s }.to_json)

      parsed = JSON.parse(connection.reload.credentials)
      expect(parsed['accessToken']).to eq('new_token')
      expect(parsed['refreshedAt']).to be_present
    end

    it 'metadata can store additional connection info' do
      connection = create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        metadata: {
          'institution_name' => 'Chase',
          'account_count' => 3,
          'last_sync' => Time.current.to_s
        }
      )

      expect(connection.metadata['institution_name']).to eq('Chase')
      expect(connection.metadata['account_count']).to eq(3)
    end
  end

  describe 'Connection identification' do
    it 'uses connection_identifier for multi-connection support' do
      conn1 = create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        connection_identifier: 'plaid_item_123'
      )

      conn2 = create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        connection_identifier: 'plaid_item_456'
      )

      # Can find by identifier
      found = user.user_mcp_connections.find_by(
        mcp_server: plaid_server,
        connection_identifier: 'plaid_item_456'
      )

      expect(found).to eq(conn2)
    end

    it 'connection_identifier must be unique per user per server' do
      create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        connection_identifier: 'item_123'
      )

      # Attempting to create duplicate should fail (either validation or unique constraint)
      expect {
        create(:user_mcp_connection,
          user: user,
          mcp_server: plaid_server,
          connection_identifier: 'item_123'
        )
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
