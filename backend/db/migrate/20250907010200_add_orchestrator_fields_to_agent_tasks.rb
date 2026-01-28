# frozen_string_literal: true

class AddOrchestratorFieldsToAgentTasks < ActiveRecord::Migration[7.1]
  def change
    change_table :agent_tasks do |t|
      t.string :orchestrator_job_id
      t.jsonb :orchestrator_state, null: false, default: {}
      t.jsonb :result_data, null: false, default: {}
      t.text :result_summary
    end

    add_index :agent_tasks, :orchestrator_job_id
  end
end
