# frozen_string_literal: true

class DropAgentActivityLogs < ActiveRecord::Migration[8.0]
  def up
    # Guard: only drop if table exists (handles partially applied environments)
    return unless table_exists?(:agent_activity_logs)

    # Remove foreign keys/indexes safely if present
    if foreign_key_exists?(:agent_activity_logs, :users)
      remove_foreign_key :agent_activity_logs, :users
    end

    # Drop the table
    drop_table :agent_activity_logs
  end

  def down
    # Recreate minimal table structure to allow rollback (data will not be restored)
    create_table :agent_activity_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.jsonb :payload, null: false, default: {}
      t.string :agentable_type, null: false
      t.bigint :agentable_id, null: false
      t.timestamps
    end

    add_index :agent_activity_logs, [:agentable_type, :agentable_id]
    add_index :agent_activity_logs, [:user_id, :created_at]
  end
end
