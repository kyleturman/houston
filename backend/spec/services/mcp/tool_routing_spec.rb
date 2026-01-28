# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MCP Tool Routing', type: :model do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user, enabled_mcp_servers: ['plaid']) }

  let!(:plaid_server) do
    server = McpServer.find_or_create_by!(name: 'plaid')
    server.update!(tools_cache: [
      { 'name' => 'plaid_get_accounts', 'description' => 'Get accounts' },
      { 'name' => 'plaid_get_transactions', 'description' => 'Get transactions' }
    ])
    server
  end

  let!(:stripe_server) do
    server = McpServer.find_or_create_by!(name: 'stripe')
    server.update!(tools_cache: [
      { 'name' => 'stripe_create_payment', 'description' => 'Create payment' }
    ])
    server
  end

  describe 'Multi-connection routing' do
    let!(:plaid_connection1) do
      create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        connection_identifier: 'item-bank1',
        credentials: { accessToken: 'token1' }.to_json,
        status: :active
      )
    end

    let!(:plaid_connection2) do
      create(:user_mcp_connection,
        user: user,
        mcp_server: plaid_server,
        connection_identifier: 'item-bank2',
        credentials: { accessToken: 'token2' }.to_json,
        status: :active
      )
    end

    it 'user can have multiple connections to same server' do
      connections = user.user_mcp_connections.where(mcp_server: plaid_server).active_connections

      expect(connections.count).to eq(2)
      expect(connections.map(&:connection_identifier)).to contain_exactly('item-bank1', 'item-bank2')
    end

    it 'can identify connections by connection_identifier' do
      connection = user.user_mcp_connections.find_by(
        mcp_server: plaid_server,
        connection_identifier: 'item-bank2'
      )

      expect(connection).to eq(plaid_connection2)
      expect(JSON.parse(connection.credentials)['accessToken']).to eq('token2')
    end

    it 'disconnected connections are excluded from active set' do
      plaid_connection1.update!(status: :disconnected)

      active = user.user_mcp_connections.where(mcp_server: plaid_server).active_connections

      expect(active.count).to eq(1)
      expect(active.first).to eq(plaid_connection2)
    end
  end

  describe 'Server tool discovery' do
    before do
      # Prevent cleanup from removing test servers
      allow(Mcp::ConnectionManager.instance).to receive(:cleanup_stale_servers!)
    end

    it 'finds correct server for tool name' do
      manager = Mcp::ConnectionManager.instance

      server_name = manager.server_name_for_tool('plaid_get_accounts')
      expect(server_name).to eq('plaid')

      server_name = manager.server_name_for_tool('stripe_create_payment')
      expect(server_name).to eq('stripe')
    end

    it 'returns nil for unknown tool' do
      manager = Mcp::ConnectionManager.instance

      server_name = manager.server_name_for_tool('nonexistent_tool')
      expect(server_name).to be_nil
    end

    it 'handles duplicate tool names across servers' do
      # Both servers have a tool with the same name
      plaid_server.update!(tools_cache: [{ 'name' => 'get_balance', 'description' => 'Plaid balance' }])
      stripe_server.update!(tools_cache: [{ 'name' => 'get_balance', 'description' => 'Stripe balance' }])

      manager = Mcp::ConnectionManager.instance
      manager.reload!

      # Should return one of the servers (actual ordering may vary)
      server_name = manager.server_name_for_tool('get_balance')
      expect(['plaid', 'stripe']).to include(server_name)
    end
  end

  describe 'Goal-level server filtering' do
    it 'goal specifies which MCP servers are enabled' do
      expect(goal.enabled_mcp_servers).to eq(['plaid'])
    end

    it 'goal with empty enabled_mcp_servers allows no MCP tools' do
      goal.update!(enabled_mcp_servers: [])

      expect(goal.enabled_mcp_servers).to be_empty
    end

    it 'goal can enable multiple servers' do
      goal.update!(enabled_mcp_servers: ['plaid', 'stripe'])

      expect(goal.enabled_mcp_servers).to contain_exactly('plaid', 'stripe')
    end
  end
end
