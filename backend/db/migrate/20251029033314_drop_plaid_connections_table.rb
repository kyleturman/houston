class DropPlaidConnectionsTable < ActiveRecord::Migration[8.0]
  def up
    # Data was already migrated to user_mcp_connections in migration 20251026211843
    # Safe to drop the old table
    drop_table :plaid_connections, if_exists: true
  end

  def down
    # Not reversible - data should stay in user_mcp_connections
    raise ActiveRecord::IrreversibleMigration
  end
end
