class AddSoftFailureFieldsToAgentTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_tasks, :error_type, :string
    add_column :agent_tasks, :error_message, :text
    add_column :agent_tasks, :retry_count, :integer, default: 0
    add_column :agent_tasks, :next_retry_at, :timestamp
    add_column :agent_tasks, :cancelled_reason, :string
    
    # Update existing failed tasks to cancelled
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE agent_tasks 
          SET status = 3, cancelled_reason = 'Migrated from failed status'
          WHERE status = 2;
        SQL
      end
    end
  end
end
