# frozen_string_literal: true

class RenameAgentFieldsAndDropExecutionPlan < ActiveRecord::Migration[8.0]
  def up
    # Goals table
    if column_exists?(:goals, :agent_state)
      rename_column :goals, :agent_state, :runtime_state
    end
    if column_exists?(:goals, :agent_memory)
      rename_column :goals, :agent_memory, :scratchpad
    end
    if column_exists?(:goals, :learnings)
      rename_column :goals, :learnings, :knowledge
    end
    if column_exists?(:goals, :execution_plan)
      remove_column :goals, :execution_plan, :jsonb
    end

    # Agent tasks table
    if column_exists?(:agent_tasks, :agent_state)
      rename_column :agent_tasks, :agent_state, :runtime_state
    end
    if column_exists?(:agent_tasks, :agent_memory)
      rename_column :agent_tasks, :agent_memory, :scratchpad
    end
    if column_exists?(:agent_tasks, :learnings)
      rename_column :agent_tasks, :learnings, :knowledge
    end
    if column_exists?(:agent_tasks, :execution_plan)
      remove_column :agent_tasks, :execution_plan, :jsonb
    end

    # Update indexes referencing renamed jsonb columns if any existed
    # (none directly on the renamed fields in current schema; llm_history indexes remain)
  end

  def down
    # Recreate execution_plan columns
    add_column :goals, :execution_plan, :jsonb, null: false, default: {}
    add_column :agent_tasks, :execution_plan, :jsonb, null: false, default: {}

    # Rename fields back if they exist
    if column_exists?(:goals, :runtime_state)
      rename_column :goals, :runtime_state, :agent_state
    end
    if column_exists?(:goals, :scratchpad)
      rename_column :goals, :scratchpad, :agent_memory
    end
    if column_exists?(:goals, :knowledge)
      rename_column :goals, :knowledge, :learnings
    end

    if column_exists?(:agent_tasks, :runtime_state)
      rename_column :agent_tasks, :runtime_state, :agent_state
    end
    if column_exists?(:agent_tasks, :scratchpad)
      rename_column :agent_tasks, :scratchpad, :agent_memory
    end
    if column_exists?(:agent_tasks, :knowledge)
      rename_column :agent_tasks, :knowledge, :learnings
    end
  end
end
