# frozen_string_literal: true

class MigrateRemoteMcpServerToConnectionMetadata < ActiveRecord::Migration[8.0]
  def up
    # Migrate all UserMcpConnections that reference RemoteMcpServer
    # Copy server config from RemoteMcpServer to metadata['remote_server_config']
    return unless table_exists?(:remote_mcp_servers)
    return unless table_exists?(:user_mcp_connections)

    # Get all connections with remote_mcp_server_id
    select_all(<<-SQL.squish).each do |conn|
      SELECT umc.id, umc.remote_mcp_server_id, umc.metadata, umc.credentials,
             rms.name, rms.url, rms.auth_type, rms.description,
             rms.metadata as server_metadata
      FROM user_mcp_connections umc
      INNER JOIN remote_mcp_servers rms ON rms.id = umc.remote_mcp_server_id
      WHERE umc.remote_mcp_server_id IS NOT NULL
    SQL

      # Parse existing metadata
      existing_metadata = begin
        conn['metadata'] ? JSON.parse(conn['metadata']) : {}
      rescue
        {}
      end

      # Parse server metadata
      server_metadata = begin
        conn['server_metadata'] ? JSON.parse(conn['server_metadata']) : {}
      rescue
        {}
      end

      # Determine source (user_added or default)
      source = server_metadata['user_added'] ? 'user_added' : 'default'

      # Build remote_server_config
      remote_server_config = {
        'name' => conn['name'],
        'display_name' => server_metadata['display_name'] || conn['name']&.titleize,
        'url' => conn['url'],
        'auth_type' => conn['auth_type'],
        'description' => conn['description'],
        'source' => source,
        # Copy OAuth metadata and client credentials if present
        'oauth_metadata' => server_metadata['oauth_metadata'],
        'client_credentials' => server_metadata['client_credentials']
      }.compact

      # Merge remote_server_config into metadata
      new_metadata = existing_metadata.merge('remote_server_config' => remote_server_config)

      # Update the connection
      execute(<<-SQL.squish)
        UPDATE user_mcp_connections
        SET metadata = #{quote(new_metadata.to_json)}
        WHERE id = #{conn['id']}
      SQL
    end

    say "Migrated #{select_value('SELECT COUNT(*) FROM user_mcp_connections WHERE remote_mcp_server_id IS NOT NULL')} connections to new remote_server_config format"
  end

  def down
    # No-op: we don't remove remote_server_config from metadata
    # The remote_mcp_server_id reference is still valid as a fallback
    say "Note: remote_server_config remains in metadata. remote_mcp_server_id still valid as fallback."
  end
end
