class RemoveUnusedAgentFields < ActiveRecord::Migration[8.0]
  def change
    # Remove unused agent_memory field from goals
    remove_column :goals, :agent_memory, :text if column_exists?(:goals, :agent_memory)
    
    # Remove unused execution_plan field from goals
    remove_column :goals, :execution_plan, :jsonb if column_exists?(:goals, :execution_plan)
    
    # Remove unused agent_memory field from agent_tasks
    remove_column :agent_tasks, :agent_memory, :text if column_exists?(:agent_tasks, :agent_memory)
    
    # Remove unused execution_plan field from agent_tasks
    remove_column :agent_tasks, :execution_plan, :jsonb if column_exists?(:agent_tasks, :execution_plan)
  end
end
