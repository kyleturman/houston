# frozen_string_literal: true

class CreateUserUrlMcpServers < ActiveRecord::Migration[8.0]
  def change
    create_table :user_url_mcp_servers do |t|
      t.references :user, null: false, foreign_key: true
      t.string :server_name, null: false
      t.text :url, null: false
      t.string :status, default: 'pending'
      t.jsonb :tools_cache, default: []
      t.string :error_message
      t.datetime :last_connected_at

      t.timestamps
    end

    add_index :user_url_mcp_servers, [:user_id, :server_name], unique: true
  end
end
