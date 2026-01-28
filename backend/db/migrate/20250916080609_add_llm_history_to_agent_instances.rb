class AddLlmHistoryToAgentInstances < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_instances, :llm_history, :jsonb, default: []
    add_index :agent_instances, :llm_history, using: :gin
  end
end
