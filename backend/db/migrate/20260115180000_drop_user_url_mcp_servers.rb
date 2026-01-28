# frozen_string_literal: true

class DropUserUrlMcpServers < ActiveRecord::Migration[8.0]
  def up
    drop_table :user_url_mcp_servers, if_exists: true
  end

  def down
    create_table :user_url_mcp_servers do |t|
      t.references :user, null: false, foreign_key: true
      t.string :server_name, null: false
      t.text :url
      t.string :status, default: 'pending'
      t.jsonb :tools_cache
      t.string :error_message
      t.datetime :last_connected_at
      t.string :display_name
      t.timestamps
    end

    add_index :user_url_mcp_servers, [:user_id, :server_name], unique: true
  end
end
