# frozen_string_literal: true

class RemoveScratchpadAndTaskLearnings < ActiveRecord::Migration[8.0]
  def up
    # Remove scratchpad from both tables
    if column_exists?(:goals, :scratchpad)
      remove_column :goals, :scratchpad
    end
    if column_exists?(:agent_tasks, :scratchpad)
      remove_column :agent_tasks, :scratchpad
    end

    # Remove knowledge/learnings from agent_tasks (keep only on goals)
    if column_exists?(:agent_tasks, :knowledge)
      remove_column :agent_tasks, :knowledge
    end

    # Rename knowledge back to learnings on goals
    if column_exists?(:goals, :knowledge)
      rename_column :goals, :knowledge, :learnings
    end
  end

  def down
    # Recreate columns if rolling back
    add_column :goals, :scratchpad, :text
    add_column :agent_tasks, :scratchpad, :text
    add_column :agent_tasks, :knowledge, :jsonb, null: false, default: []
    
    if column_exists?(:goals, :learnings)
      rename_column :goals, :learnings, :knowledge
    end
  end
end
