class CreateUserMcpConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :user_mcp_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.references :remote_mcp_server, null: false, foreign_key: true
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at
      t.json :metadata, default: {}
      t.string :status, default: 'pending'
      t.string :code_verifier
      t.string :state

      t.timestamps
    end

    add_index :user_mcp_connections, [:user_id, :remote_mcp_server_id], unique: true, name: 'index_user_mcp_connections_unique'
  end
end
