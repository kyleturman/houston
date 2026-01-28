# frozen_string_literal: true

class AddAgentFieldsToGoals < ActiveRecord::Migration[8.0]
  def change
    change_table :goals, bulk: true do |t|
      t.text :agent_instructions
      t.string :agent_job_id
      t.jsonb :agent_state, null: false, default: {}
      t.datetime :last_agent_run
    end

    add_index :goals, :agent_job_id
  end
end
