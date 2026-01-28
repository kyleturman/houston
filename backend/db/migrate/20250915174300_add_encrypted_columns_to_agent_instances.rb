class AddEncryptedColumnsToAgentInstances < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_instances, :execution_plan, :jsonb, default: {}
    add_column :agent_instances, :learnings, :jsonb, default: []
    add_column :agent_instances, :agent_memory, :text
  end
end
