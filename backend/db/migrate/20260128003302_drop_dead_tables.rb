# frozen_string_literal: true

class DropDeadTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :oauth_credentials, if_exists: true
    drop_table :user_tool_configs, if_exists: true
  end

  def down
    create_table :oauth_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :server_name, null: false
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at
      t.text :metadata
      t.timestamps
    end

    create_table :user_tool_configs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :tool_name, null: false
      t.text :config
      t.timestamps
    end
    add_index :user_tool_configs, [:user_id, :tool_name], unique: true
  end
end
