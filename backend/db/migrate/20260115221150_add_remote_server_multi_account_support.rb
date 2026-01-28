# frozen_string_literal: true

class AddRemoteServerMultiAccountSupport < ActiveRecord::Migration[8.0]
  def up
    # Add remote_server_name column for DB-level uniqueness constraint
    # This is denormalized from metadata['remote_server_config']['name']
    # for remote connections (where mcp_server_id is NULL)
    add_column :user_mcp_connections, :remote_server_name, :string

    # Backfill existing remote connections
    execute(<<-SQL.squish)
      UPDATE user_mcp_connections
      SET remote_server_name = metadata->'remote_server_config'->>'name'
      WHERE mcp_server_id IS NULL
        AND metadata->'remote_server_config'->>'name' IS NOT NULL
    SQL

    # Also backfill from legacy remote_mcp_server for connections that haven't been migrated
    execute(<<-SQL.squish)
      UPDATE user_mcp_connections umc
      SET remote_server_name = rms.name
      FROM remote_mcp_servers rms
      WHERE umc.remote_mcp_server_id = rms.id
        AND umc.remote_server_name IS NULL
    SQL

    # For remote connections without connection_identifier, set a default UUID
    # This maintains backward compatibility (single connection = single UUID)
    execute(<<-SQL.squish)
      UPDATE user_mcp_connections
      SET connection_identifier = gen_random_uuid()::text
      WHERE mcp_server_id IS NULL
        AND connection_identifier IS NULL
    SQL

    # Add unique index for remote server connections
    # This allows multiple connections per user per remote server (via connection_identifier)
    # but enforces uniqueness at DB level
    add_index :user_mcp_connections,
              [:user_id, :remote_server_name, :connection_identifier],
              unique: true,
              where: 'remote_server_name IS NOT NULL',
              name: 'idx_user_remote_server_connection'

    # Add index for querying by remote_server_name
    add_index :user_mcp_connections, :remote_server_name,
              where: 'remote_server_name IS NOT NULL',
              name: 'idx_remote_server_name'
  end

  def down
    remove_index :user_mcp_connections, name: 'idx_user_remote_server_connection'
    remove_index :user_mcp_connections, name: 'idx_remote_server_name'
    remove_column :user_mcp_connections, :remote_server_name
  end
end
