class AddOriginToolActivityIdToAgentTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_tasks, :origin_tool_activity_id, :string
    add_index :agent_tasks, :origin_tool_activity_id
  end
end
