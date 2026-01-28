# frozen_string_literal: true

class CreateMcpServers < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_servers do |t|
      t.string :name, null: false
      t.string :transport, null: false, default: 'http'
      t.string :endpoint
      t.string :command
      t.boolean :healthy, null: false, default: false
      t.datetime :last_seen_at
      t.jsonb :tools_cache, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :mcp_servers, :name, unique: true
  end
end
