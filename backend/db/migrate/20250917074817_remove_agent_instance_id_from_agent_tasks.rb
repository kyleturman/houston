class RemoveAgentInstanceIdFromAgentTasks < ActiveRecord::Migration[8.0]
  def up
    # Remove the foreign key constraint first
    remove_foreign_key :agent_tasks, :agent_instances, name: :fk_rails_3a258ecc73
    
    # Then remove the column
    remove_column :agent_tasks, :agent_instance_id
    
    puts "✅ Removed agent_instance_id column and foreign key constraint from agent_tasks"
  end
  
  def down
    # Add the column back
    add_column :agent_tasks, :agent_instance_id, :integer
    
    # Add the foreign key constraint back
    add_foreign_key :agent_tasks, :agent_instances, name: :fk_rails_3a258ecc73
  end
end
