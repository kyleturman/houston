class AddAgentFieldsToGoalsAndTasks < ActiveRecord::Migration[8.0]
  def change
    # Add missing agent fields to goals table (agent_state already exists)
    add_column :goals, :llm_history, :jsonb, default: [], null: false unless column_exists?(:goals, :llm_history)
    add_column :goals, :execution_plan, :jsonb, default: {}, null: false unless column_exists?(:goals, :execution_plan)
    add_column :goals, :learnings, :jsonb, default: [], null: false unless column_exists?(:goals, :learnings)
    add_column :goals, :agent_memory, :text unless column_exists?(:goals, :agent_memory)

    # Add agent fields to agent_tasks table
    add_column :agent_tasks, :agent_state, :jsonb, default: {}, null: false unless column_exists?(:agent_tasks, :agent_state)
    add_column :agent_tasks, :llm_history, :jsonb, default: [], null: false unless column_exists?(:agent_tasks, :llm_history)
    add_column :agent_tasks, :execution_plan, :jsonb, default: {}, null: false unless column_exists?(:agent_tasks, :execution_plan)
    add_column :agent_tasks, :learnings, :jsonb, default: [], null: false unless column_exists?(:agent_tasks, :learnings)
    add_column :agent_tasks, :agent_memory, :text unless column_exists?(:agent_tasks, :agent_memory)

    # Add indexes for performance (only if columns exist)
    add_index :goals, :llm_history, using: :gin unless index_exists?(:goals, :llm_history)
    add_index :agent_tasks, :llm_history, using: :gin unless index_exists?(:agent_tasks, :llm_history)

    # Migrate existing AgentInstance data to goals and tasks
    reversible do |dir|
      dir.up do
        # Migrate goal agent instances
        execute <<-SQL
          UPDATE goals 
          SET 
            agent_state = COALESCE(ai.state, '{}'),
            llm_history = COALESCE(ai.llm_history, '[]'),
            execution_plan = COALESCE(ai.execution_plan, '{}'),
            learnings = COALESCE(ai.learnings, '[]'),
            agent_memory = ai.agent_memory
          FROM agent_instances ai 
          WHERE goals.id = ai.goal_id 
            AND ai.agent_task_id IS NULL
            AND ai.agent_type = 0;
        SQL

        # Migrate task agent instances
        execute <<-SQL
          UPDATE agent_tasks 
          SET 
            agent_state = COALESCE(ai.state, '{}'),
            llm_history = COALESCE(ai.llm_history, '[]'),
            execution_plan = COALESCE(ai.execution_plan, '{}'),
            learnings = COALESCE(ai.learnings, '[]'),
            agent_memory = ai.agent_memory
          FROM agent_instances ai 
          WHERE agent_tasks.id = ai.agent_task_id 
            AND ai.agent_type = 1;
        SQL
      end
    end
  end
end
