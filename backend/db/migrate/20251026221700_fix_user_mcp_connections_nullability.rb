class FixUserMcpConnectionsNullability < ActiveRecord::Migration[8.0]
  def change
    change_column_null :user_mcp_connections, :remote_mcp_server_id, true
  end
end
