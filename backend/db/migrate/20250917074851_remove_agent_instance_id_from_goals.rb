class RemoveAgentInstanceIdFromGoals < ActiveRecord::Migration[8.0]
  def up
    # Remove the foreign key constraint first
    remove_foreign_key :goals, :agent_instances, name: :fk_rails_41330997aa
    
    # Then remove the column
    remove_column :goals, :agent_instance_id
    
    puts "✅ Removed agent_instance_id column and foreign key constraint from goals"
  end
  
  def down
    # Add the column back
    add_column :goals, :agent_instance_id, :integer
    
    # Add the foreign key constraint back
    add_foreign_key :goals, :agent_instances, name: :fk_rails_41330997aa
  end
end
