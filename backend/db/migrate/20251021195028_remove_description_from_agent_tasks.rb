class RemoveDescriptionFromAgentTasks < ActiveRecord::Migration[8.0]
  def change
    remove_column :agent_tasks, :description, :text
  end
end
