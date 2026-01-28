# frozen_string_literal: true

class CreateAgentInstances < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_instances do |t|
      t.references :user, null: false, foreign_key: true
      t.references :goal, null: true, foreign_key: true
      t.references :agent_task, null: true, foreign_key: true

      t.integer :agent_type, null: false, default: 0 # { goal: 0, task: 1 }
      t.integer :status, null: false, default: 0    # { active: 0, paused: 1, completed: 2, failed: 3 }

      t.string :orchestrator_job_id
      t.jsonb :state, null: false, default: {}

      t.timestamps
    end

    add_index :agent_instances, :orchestrator_job_id
  end
end
