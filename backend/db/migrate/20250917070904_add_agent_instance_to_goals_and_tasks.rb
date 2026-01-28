class AddAgentInstanceToGoalsAndTasks < ActiveRecord::Migration[8.0]
  def change
    # Add agent_instance_id to goals table
    add_reference :goals, :agent_instance, null: true, foreign_key: true
    
    # Add agent_instance_id to agent_tasks table  
    add_reference :agent_tasks, :agent_instance, null: true, foreign_key: true
    
    # Populate the new fields with existing agent instances
    reversible do |dir|
      dir.up do
        # For each goal, set agent_instance_id to the most recent agent
        execute <<-SQL
          UPDATE goals 
          SET agent_instance_id = (
            SELECT id FROM agent_instances 
            WHERE agent_instances.goal_id = goals.id 
            AND agent_instances.agent_type = 0
            ORDER BY created_at DESC 
            LIMIT 1
          )
          WHERE EXISTS (
            SELECT 1 FROM agent_instances 
            WHERE agent_instances.goal_id = goals.id 
            AND agent_instances.agent_type = 0
          );
        SQL
        
        # For each task, set agent_instance_id to the most recent agent
        execute <<-SQL
          UPDATE agent_tasks 
          SET agent_instance_id = (
            SELECT id FROM agent_instances 
            WHERE agent_instances.agent_task_id = agent_tasks.id 
            AND agent_instances.agent_type = 1
            ORDER BY created_at DESC 
            LIMIT 1
          )
          WHERE EXISTS (
            SELECT 1 FROM agent_instances 
            WHERE agent_instances.agent_task_id = agent_tasks.id 
            AND agent_instances.agent_type = 1
          );
        SQL
      end
    end
  end
end
