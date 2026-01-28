# frozen_string_literal: true

class CreateAgentActivityLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_activity_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :goal, null: true, foreign_key: true
      t.references :agent_task, null: true, foreign_key: true

      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.integer :tokens_in, null: true
      t.integer :tokens_out, null: true

      t.timestamps
    end

    add_index :agent_activity_logs, [:user_id, :created_at]
    add_index :agent_activity_logs, [:agent_task_id, :created_at]
  end
end
