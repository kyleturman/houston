class EnhanceUserMcpConnectionsForMultiple < ActiveRecord::Migration[8.0]
  def change
    # Add mcp_server_id to support both local and remote servers
    add_reference :user_mcp_connections, :mcp_server, foreign_key: true, index: true

    # Add connection_identifier to support multiple connections per server
    add_column :user_mcp_connections, :connection_identifier, :string

    # Rename access_token to credentials (will store JSON)
    rename_column :user_mcp_connections, :access_token, :credentials

    # Update status enum to support active/disconnected states
    # Keep existing values for backward compat with remote servers
    change_column_default :user_mcp_connections, :status, from: nil, to: 'active'

    # Add unique index for user + server + connection
    add_index :user_mcp_connections, [:user_id, :mcp_server_id, :connection_identifier],
              unique: true, name: 'idx_user_server_connection'

    # Add index for active connections
    add_index :user_mcp_connections, [:mcp_server_id, :status]
  end
end
