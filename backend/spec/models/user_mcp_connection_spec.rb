# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserMcpConnection, type: :model do
  let(:user) { create(:user) }

  describe 'validations' do
    it 'requires user' do
      connection = UserMcpConnection.new(remote_mcp_server: create(:remote_mcp_server))
      expect(connection).not_to be_valid
      expect(connection.errors[:user]).to include('must exist')
    end

    it 'requires server reference or remote_server_config' do
      connection = UserMcpConnection.new(user: user)
      expect(connection).not_to be_valid
      expect(connection.errors[:base]).to include('Connection must have server reference or remote_server_config')
    end

    it 'is valid with remote_server_config' do
      connection = build(:user_mcp_connection, :remote_with_config, user: user)
      expect(connection).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to user' do
      expect(UserMcpConnection.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
  end

  describe 'defaults' do
    it 'defaults status to active' do
      remote_server = RemoteMcpServer.create!(name: 'test_server', url: 'https://example.com', auth_type: 'oauth2')
      connection = UserMcpConnection.create!(user: user, remote_mcp_server: remote_server)
      expect(connection.status).to eq('active')
    end

    it 'defaults metadata to empty hash' do
      remote_server = RemoteMcpServer.create!(name: 'test_server', url: 'https://example.com', auth_type: 'oauth2')
      connection = UserMcpConnection.create!(user: user, remote_mcp_server: remote_server)
      expect(connection.metadata).to eq({})
    end
  end

  describe 'callbacks' do
    describe '#sync_remote_server_name' do
      it 'syncs remote_server_name from remote_server_config' do
        connection = build(:user_mcp_connection, :remote_with_config, user: user)
        connection.valid?
        expect(connection.remote_server_name).to eq('test-server')
      end

      it 'syncs remote_server_name from legacy remote_mcp_server' do
        remote_server = create(:remote_mcp_server, name: 'legacy-server')
        connection = build(:user_mcp_connection, :remote, user: user, remote_mcp_server: remote_server)
        connection.valid?
        expect(connection.remote_server_name).to eq('legacy-server')
      end
    end

    describe '#ensure_connection_identifier' do
      it 'generates UUID for remote connections without identifier' do
        connection = build(:user_mcp_connection, :remote_with_config, user: user, connection_identifier: nil)
        connection.valid?
        expect(connection.connection_identifier).to be_present
        expect(connection.connection_identifier).to match(/^[0-9a-f-]{36}$/)
      end

      it 'preserves existing connection_identifier' do
        connection = build(:user_mcp_connection, :remote_with_config, user: user, connection_identifier: 'custom-id')
        connection.valid?
        expect(connection.connection_identifier).to eq('custom-id')
      end
    end
  end

  describe 'scopes' do
    let!(:authorized_connection) { create(:user_mcp_connection, user: user, status: 'authorized') }
    let!(:pending_connection) { create(:user_mcp_connection, user: user, status: 'pending') }

    it 'can filter by status' do
      expect(UserMcpConnection.where(status: 'authorized')).to include(authorized_connection)
      expect(UserMcpConnection.where(status: 'authorized')).not_to include(pending_connection)
    end

    describe '.for_remote_server' do
      let!(:notion_conn1) { create(:user_mcp_connection, :remote_with_config, user: user, server_name: 'notion') }
      let!(:notion_conn2) { create(:user_mcp_connection, :remote_with_config, user: user, server_name: 'notion', connection_identifier: 'workspace-2') }
      let!(:slack_conn) { create(:user_mcp_connection, :remote_with_config, user: user, server_name: 'slack') }

      it 'filters by remote_server_name' do
        notion_connections = UserMcpConnection.for_remote_server('notion')
        expect(notion_connections).to include(notion_conn1, notion_conn2)
        expect(notion_connections).not_to include(slack_conn)
      end
    end

    describe '.active_remote_connections_for' do
      let!(:active_conn) { create(:user_mcp_connection, :remote_with_config, user: user, server_name: 'notion', status: 'active') }
      let!(:pending_conn) { create(:user_mcp_connection, :remote_with_config, user: user, server_name: 'notion', status: 'pending', connection_identifier: 'ws-2') }

      it 'returns only active connections for user and server' do
        connections = UserMcpConnection.active_remote_connections_for(user, 'notion')
        expect(connections).to include(active_conn)
        expect(connections).not_to include(pending_conn)
      end
    end
  end

  describe 'multi-account support' do
    describe '#set_connection_identifier_from_oauth' do
      let(:connection) { build(:user_mcp_connection, :remote_with_config, user: user) }

      it 'sets connection_identifier from workspace_id' do
        connection.set_connection_identifier_from_oauth({ 'workspace_id' => 'ws-123' })
        expect(connection.connection_identifier).to eq('ws-123')
      end

      it 'sets connection_identifier from team_id (Slack)' do
        connection.set_connection_identifier_from_oauth({ 'team_id' => 'T123456' })
        expect(connection.connection_identifier).to eq('T123456')
      end

      it 'stores workspace_name in metadata' do
        connection.set_connection_identifier_from_oauth({
          'workspace_id' => 'ws-123',
          'workspace_name' => 'My Workspace'
        })
        expect(connection.metadata['workspace_name']).to eq('My Workspace')
      end

      it 'handles team name from nested structure' do
        connection.set_connection_identifier_from_oauth({
          'team_id' => 'T123',
          'team' => { 'name' => 'Team Name' }
        })
        expect(connection.metadata['workspace_name']).to eq('Team Name')
      end
    end

    it 'allows multiple connections per user per remote server' do
      conn1 = create(:user_mcp_connection, :remote_with_config, user: user, server_name: 'notion', connection_identifier: 'ws-1')
      conn2 = create(:user_mcp_connection, :remote_with_config, user: user, server_name: 'notion', connection_identifier: 'ws-2')

      expect(conn1).to be_persisted
      expect(conn2).to be_persisted
      expect(UserMcpConnection.for_remote_server('notion').count).to eq(2)
    end

    it 'prevents duplicate connections with same identifier' do
      create(:user_mcp_connection, :remote_with_config, user: user, server_name: 'notion', connection_identifier: 'ws-1')

      duplicate = build(:user_mcp_connection, :remote_with_config, user: user, server_name: 'notion', connection_identifier: 'ws-1')

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'server accessors' do
    describe '#server_name' do
      it 'returns name from remote_server_config' do
        connection = build(:user_mcp_connection, :remote_with_config, user: user)
        expect(connection.server_name).to eq('test-server')
      end

      it 'returns name from legacy remote_mcp_server' do
        remote_server = create(:remote_mcp_server, name: 'legacy-name')
        connection = build(:user_mcp_connection, :remote, user: user, remote_mcp_server: remote_server)
        expect(connection.server_name).to eq('legacy-name')
      end
    end

    describe '#user_added?' do
      it 'returns true for user-added servers' do
        connection = build(:user_mcp_connection, :user_added, user: user)
        expect(connection.user_added?).to be true
      end

      it 'returns false for default servers' do
        connection = build(:user_mcp_connection, :remote_with_config, user: user)
        expect(connection.user_added?).to be false
      end
    end

    describe '#workspace_name' do
      it 'returns workspace_name from metadata' do
        connection = build(:user_mcp_connection, :with_workspace, user: user, workspace_name: 'Test Workspace')
        expect(connection.workspace_name).to eq('Test Workspace')
      end
    end
  end
end
