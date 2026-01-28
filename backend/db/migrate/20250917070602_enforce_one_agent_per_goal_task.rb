class EnforceOneAgentPerGoalTask < ActiveRecord::Migration[8.0]
  def up
    # First, clean up existing duplicate agents by keeping only the most recent one
    puts "Cleaning up duplicate goal agents..."
    
    # For each goal with multiple agents, keep only the most recent one
    execute <<-SQL
      DELETE FROM agent_instances 
      WHERE id NOT IN (
        SELECT DISTINCT ON (goal_id, agent_type) id
        FROM agent_instances 
        WHERE goal_id IS NOT NULL AND agent_type = 0
        ORDER BY goal_id, agent_type, created_at DESC
      ) AND goal_id IS NOT NULL AND agent_type = 0;
    SQL
    
    puts "Cleaning up duplicate task agents..."
    
    # For each task with multiple agents, keep only the most recent one
    execute <<-SQL
      DELETE FROM agent_instances 
      WHERE id NOT IN (
        SELECT DISTINCT ON (agent_task_id, agent_type) id
        FROM agent_instances 
        WHERE agent_task_id IS NOT NULL AND agent_type = 1
        ORDER BY agent_task_id, agent_type, created_at DESC
      ) AND agent_task_id IS NOT NULL AND agent_type = 1;
    SQL
    
    # Remove the old partial unique indexes (they only prevent multiple active agents)
    remove_index :agent_instances, name: :index_unique_active_goal_agent_instance
    remove_index :agent_instances, name: :index_unique_active_task_agent_instance
    
    # Add new unique constraints that prevent ANY duplicate agents (regardless of status)
    # For goal agents: one agent per goal (goal_id + agent_type=0)
    add_index :agent_instances, [:goal_id, :agent_type], 
              unique: true, 
              where: "goal_id IS NOT NULL AND agent_type = 0",
              name: :index_unique_goal_agent_instance
              
    # For task agents: one agent per task (agent_task_id + agent_type=1)
    add_index :agent_instances, [:agent_task_id, :agent_type], 
              unique: true, 
              where: "agent_task_id IS NOT NULL AND agent_type = 1", 
              name: :index_unique_task_agent_instance
    
    puts "✅ Enforced one agent per goal/task constraint"
  end
  
  def down
    # Restore the old partial unique indexes
    remove_index :agent_instances, name: :index_unique_goal_agent_instance
    remove_index :agent_instances, name: :index_unique_task_agent_instance
    
    add_index :agent_instances, [:goal_id, :agent_type, :status], 
              unique: true, 
              where: "goal_id IS NOT NULL AND agent_type = 0 AND status = 0",
              name: :index_unique_active_goal_agent_instance
              
    add_index :agent_instances, [:agent_task_id, :agent_type, :status], 
              unique: true, 
              where: "agent_task_id IS NOT NULL AND agent_type = 1 AND status = 0",
              name: :index_unique_active_task_agent_instance
  end
end
