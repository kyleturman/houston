# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::ConnectionManager do
  let(:manager) { described_class.instance }

  before do
    # Reset the singleton state before each test
    manager.instance_variable_set(:@servers, {})
    manager.instance_variable_set(:@loaded, false)
  end

  describe 'smoke test', :core do
    it 'can load all user connections without errors' do
      # This catches corrupted encrypted data, missing associations, etc.
      # Uses real DB data to catch production issues
      expect { manager.send(:load_user_connections!) }.not_to raise_error
    end

    it 'can iterate all connections and access key fields' do
      # Verify each connection's encrypted fields can be decrypted
      UserMcpConnection.find_each do |conn|
        expect { conn.parsed_credentials }.not_to raise_error
        expect { conn.server_url }.not_to raise_error
        expect { conn.server_name }.not_to raise_error
      end
    end
  end

  describe '#load!' do
    context 'with default servers from JSON config' do
      before do
        # Ensure DefaultServersService is loaded
        allow(Mcp::DefaultServersService.instance).to receive(:list_all).and_return([
          Mcp::DefaultServersService::ServerConfig.new(
            name: 'notion',
            display_name: 'Notion',
            description: 'Notion MCP server',
            url: 'https://mcp.notion.com/mcp',
            auth_type: 'oauth_consent',
            enabled: true
          )
        ])
      end

      it 'loads without error' do
        expect { manager.reload! }.not_to raise_error
      end
    end
  end

  describe '#register_remote_server' do
    it 'raises error for nil URL' do
      expect {
        manager.register_remote_server('test', nil, {})
      }.to raise_error(URI::InvalidURIError)
    end

    it 'registers a server with valid URL' do
      expect {
        manager.register_remote_server('test-server', 'https://example.com/mcp', {})
      }.not_to raise_error

      expect(manager.instance_variable_get(:@servers)['test-server']).to be_present
    end
  end

  describe '#load_user_connections!' do
    let(:user) { create(:user) }

    context 'with active direct connection (new model)' do
      let!(:connection) do
        UserMcpConnection.create!(
          user: user,
          credentials: { 'url' => 'https://custom.mcp.example.com/api' }.to_json,
          status: 'active',
          metadata: {
            'remote_server_config' => {
              'name' => 'custom-mcp',
              'display_name' => 'Custom MCP',
              'auth_type' => 'direct',
              'source' => 'user_added'
            }
          }
        )
      end

      it 'registers direct servers from UserMcpConnection with remote_server_config' do
        manager.send(:load_user_connections!)

        server_record = manager.instance_variable_get(:@servers)['custom-mcp']
        expect(server_record).to be_present
        expect(server_record.server.endpoint).to eq('https://custom.mcp.example.com/api')
      end
    end

    context 'with active connection to default server' do
      let!(:connection) do
        UserMcpConnection.create!(
          user: user,
          credentials: { 'access_token' => 'secret123' }.to_json,
          status: 'active',
          metadata: {
            'remote_server_config' => {
              'name' => 'notion',
              'display_name' => 'Notion',
              'url' => 'https://mcp.notion.com/mcp',
              'auth_type' => 'oauth_consent',
              'source' => 'default'
            }
          }
        )
      end

      it 'registers OAuth servers from UserMcpConnection' do
        manager.send(:load_user_connections!)

        server_record = manager.instance_variable_get(:@servers)['notion']
        expect(server_record).to be_present
        expect(server_record.server.endpoint).to eq('https://mcp.notion.com/mcp')
      end
    end

    context 'with disconnected connection' do
      let!(:connection) do
        UserMcpConnection.create!(
          user: user,
          credentials: { 'url' => 'https://custom.mcp.example.com/api' }.to_json,
          status: 'disconnected',
          metadata: {
            'remote_server_config' => {
              'name' => 'custom-mcp',
              'display_name' => 'Custom MCP',
              'auth_type' => 'direct',
              'source' => 'user_added'
            }
          }
        )
      end

      it 'skips disconnected connections' do
        manager.send(:load_user_connections!)

        expect(manager.instance_variable_get(:@servers)['custom-mcp']).to be_nil
      end
    end

    # LEGACY: Test backward compatibility with remote_mcp_server_id
    context 'with legacy remote_mcp_server reference' do
      let!(:remote_server) do
        RemoteMcpServer.create!(
          name: 'legacy-server',
          auth_type: 'direct',
          url: nil,
          metadata: { 'user_added' => true }
        )
      end

      let!(:connection) do
        UserMcpConnection.create!(
          user: user,
          remote_mcp_server: remote_server,
          credentials: { 'url' => 'https://legacy.mcp.example.com/api' }.to_json,
          status: 'active'
        )
      end

      it 'still works with legacy remote_mcp_server reference' do
        manager.send(:load_user_connections!)

        server_record = manager.instance_variable_get(:@servers)['legacy-server']
        expect(server_record).to be_present
        expect(server_record.server.endpoint).to eq('https://legacy.mcp.example.com/api')
      end
    end
  end
end
