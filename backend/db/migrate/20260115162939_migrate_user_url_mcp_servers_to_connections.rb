# frozen_string_literal: true

class MigrateUserUrlMcpServersToConnections < ActiveRecord::Migration[8.0]
  def up
    # First, make URL column nullable for auth_type='direct' servers
    # (URL is stored in UserMcpConnection.credentials for these servers)
    change_column_null :remote_mcp_servers, :url, true

    # Migrate UserUrlMcpServer records to RemoteMcpServer + UserMcpConnection
    return unless table_exists?(:user_url_mcp_servers)

    # Use raw SQL to avoid model dependencies
    select_all("SELECT * FROM user_url_mcp_servers").each do |url_server|
      slug = url_server['server_name'].to_s.downcase

      # Check if RemoteMcpServer already exists
      remote = select_one("SELECT id FROM remote_mcp_servers WHERE name = #{quote(slug)}")

      if remote.nil?
        # Create RemoteMcpServer with auth_type='direct'
        metadata = { 'display_name' => url_server['display_name'] || slug.titleize, 'user_added' => true, 'migrated_at' => Time.current.iso8601 }
        execute(<<-SQL.squish)
          INSERT INTO remote_mcp_servers (name, auth_type, metadata, created_at, updated_at)
          VALUES (
            #{quote(slug)},
            'direct',
            #{quote(metadata.to_json)},
            NOW(),
            NOW()
          )
        SQL
        remote = select_one("SELECT id FROM remote_mcp_servers WHERE name = #{quote(slug)}")
      end

      remote_server_id = remote['id']

      # Check if UserMcpConnection already exists
      existing = select_one(<<-SQL.squish)
        SELECT id FROM user_mcp_connections
        WHERE user_id = #{url_server['user_id']}
        AND remote_mcp_server_id = #{remote_server_id}
      SQL

      if existing.nil?
        # Map status: connected -> active, others -> disconnected
        new_status = url_server['status'] == 'connected' ? 'active' : 'disconnected'

        # Parse tools_cache if present
        tools_cache = begin
          url_server['tools_cache'] ? JSON.parse(url_server['tools_cache']) : []
        rescue
          []
        end

        # Build metadata
        metadata = {
          'tools_cache' => tools_cache,
          'error_message' => url_server['error_message'],
          'last_connected_at' => url_server['last_connected_at']&.to_s,
          'display_name' => url_server['display_name'],
          'migrated_from' => 'UserUrlMcpServer'
        }.compact

        # Build credentials with URL
        credentials = { 'url' => url_server['url'] }.to_json

        execute(<<-SQL.squish)
          INSERT INTO user_mcp_connections (user_id, remote_mcp_server_id, credentials, status, metadata, created_at, updated_at)
          VALUES (
            #{url_server['user_id']},
            #{remote_server_id},
            #{quote(credentials)},
            #{quote(new_status)},
            #{quote(metadata.to_json)},
            NOW(),
            NOW()
          )
        SQL
      end
    end
  end

  def down
    # Mark migrated connections for review (don't auto-delete)
    execute(<<-SQL.squish)
      UPDATE user_mcp_connections
      SET status = 'revoked'
      WHERE metadata->>'migrated_from' = 'UserUrlMcpServer'
    SQL
  end
end
