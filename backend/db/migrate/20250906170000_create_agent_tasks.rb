# frozen_string_literal: true

class CreateAgentTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :goal, null: true, foreign_key: true
      t.bigint :parent_task_id, null: true, index: true

      t.string :title, null: false
      t.text :description
      t.text :instructions

      # Enums (integers)
      t.integer :status, null: false, default: 0
      t.integer :priority, null: false, default: 1

      t.string :blocking_reason
      t.jsonb :context_data, null: false, default: {}

      t.string :agent_job_id

      t.timestamps
    end

    add_index :agent_tasks, :status
    add_index :agent_tasks, :priority
    add_index :agent_tasks, :agent_job_id
    add_index :agent_tasks, [:user_id, :status]

    add_foreign_key :agent_tasks, :agent_tasks, column: :parent_task_id
  end
end
