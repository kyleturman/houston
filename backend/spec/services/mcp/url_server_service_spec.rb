# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::UrlServerService do
  let(:user) { create(:user) }
  let(:server_name) { 'custom-server' }
  let(:server_url) { 'https://mcp.example.com/api' }

  describe '.add_server' do
    context 'when server requires no auth' do
      before do
        allow(Mcp::ServerDiscoveryService).to receive(:discover).and_return(
          Mcp::ServerDiscoveryService::DiscoveryResult.new(auth_type: :none, status: :success)
        )
        stub_request(:post, server_url).to_return(
          status: 200,
          body: { jsonrpc: '2.0', result: { tools: [{ name: 'tool_one' }] } }.to_json
        )
      end

      it 'connects and returns enabled' do
        result = described_class.add_server(user: user, name: server_name, url: server_url)

        expect(result[:success]).to be true
        expect(result[:action]).to eq(:enabled)

        # Check UserMcpConnection was created with remote_server_config
        connection = user.user_mcp_connections.remote_connections.find { |c| c.server_name == server_name.downcase }
        expect(connection).to be_present
        expect(connection.status).to eq('active')
        expect(connection.server_url).to eq(server_url)
        expect(connection.server_auth_type).to eq('direct')
        expect(connection.user_added?).to be true
      end
    end

    context 'when server requires OAuth' do
      before do
        allow(Mcp::ServerDiscoveryService).to receive(:discover).and_return(
          Mcp::ServerDiscoveryService::DiscoveryResult.new(
            auth_type: :oauth,
            status: :needs_auth,
            oauth_metadata: { 'authorization_endpoint' => 'https://example.com/oauth' }
          )
        )
      end

      it 'creates server record and returns available' do
        result = described_class.add_server(user: user, name: server_name, url: server_url)

        expect(result[:success]).to be true
        expect(result[:action]).to eq(:available)
        expect(result[:needs_auth]).to be true

        # Check UserMcpConnection was created with pending status and OAuth metadata
        connection = user.user_mcp_connections.remote_connections.find { |c| c.server_name == server_name.downcase }
        expect(connection).to be_present
        expect(connection.status).to eq('pending')
        expect(connection.server_auth_type).to eq('oauth_consent')

        # Check McpServer was also created (for tool registration)
        expect(McpServer.find_by(name: server_name.downcase)).to be_present
      end
    end

    context 'when discovery fails' do
      before do
        allow(Mcp::ServerDiscoveryService).to receive(:discover).and_return(
          Mcp::ServerDiscoveryService::DiscoveryResult.new(auth_type: :unknown, status: :error, error: 'Timeout')
        )
      end

      it 'returns error' do
        result = described_class.add_server(user: user, name: server_name, url: server_url)

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end
  end

  describe '.disconnect' do
    let!(:connection) do
      UserMcpConnection.create!(
        user: user,
        credentials: { 'url' => server_url }.to_json,
        status: 'active',
        metadata: {
          'remote_server_config' => {
            'name' => server_name.downcase,
            'display_name' => server_name,
            'url' => server_url,
            'auth_type' => 'direct',
            'source' => 'user_added'
          }
        }
      )
    end
    let!(:mcp_server) { McpServer.create!(name: server_name.downcase, endpoint: server_url) }

    it 'removes records' do
      result = described_class.disconnect(user: user, server_name: server_name)

      expect(result[:success]).to be true
      expect(UserMcpConnection.find_by(id: connection.id)).to be_nil
      expect(McpServer.find_by(id: mcp_server.id)).to be_nil
    end
  end
end
