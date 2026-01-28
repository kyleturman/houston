class RemoveOldUniqueConstraintsFromAgentInstances < ActiveRecord::Migration[8.0]
  def up
    # Remove the old unique constraints that are no longer needed with has_one relationships
    remove_index :agent_instances, name: :index_unique_goal_agent_instance
    remove_index :agent_instances, name: :index_unique_task_agent_instance
    
    puts "✅ Removed old unique constraints - has_one relationships will handle uniqueness"
  end
  
  def down
    # Restore the old unique constraints
    add_index :agent_instances, [:goal_id, :agent_type], 
              unique: true, 
              where: "goal_id IS NOT NULL AND agent_type = 0",
              name: :index_unique_goal_agent_instance
              
    add_index :agent_instances, [:agent_task_id, :agent_type], 
              unique: true, 
              where: "agent_task_id IS NOT NULL AND agent_type = 1", 
              name: :index_unique_task_agent_instance
  end
end
