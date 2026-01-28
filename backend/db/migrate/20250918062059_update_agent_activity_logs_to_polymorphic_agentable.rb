class UpdateAgentActivityLogsToPolymorphicAgentable < ActiveRecord::Migration[8.0]
  def change
    # Add polymorphic columns for agentable
    add_column :agent_activity_logs, :agentable_type, :string
    add_column :agent_activity_logs, :agentable_id, :bigint

    # Add index for polymorphic association
    add_index :agent_activity_logs, [:agentable_type, :agentable_id]

    # Migrate existing data from agent_instance to polymorphic agentable
    reversible do |dir|
      dir.up do
        # Migrate goal agent instances to goals
        execute <<-SQL
          UPDATE agent_activity_logs 
          SET 
            agentable_type = 'Goal',
            agentable_id = ai.goal_id
          FROM agent_instances ai 
          WHERE agent_activity_logs.agent_instance_id = ai.id 
            AND ai.goal_id IS NOT NULL 
            AND ai.agent_task_id IS NULL
            AND ai.agent_type = 0;
        SQL

        # Migrate task agent instances to agent_tasks
        execute <<-SQL
          UPDATE agent_activity_logs 
          SET 
            agentable_type = 'AgentTask',
            agentable_id = ai.agent_task_id
          FROM agent_instances ai 
          WHERE agent_activity_logs.agent_instance_id = ai.id 
            AND ai.agent_task_id IS NOT NULL 
            AND ai.agent_type = 1;
        SQL
      end
    end

    # Make polymorphic columns not null after migration
    change_column_null :agent_activity_logs, :agentable_type, false
    change_column_null :agent_activity_logs, :agentable_id, false
  end
end
