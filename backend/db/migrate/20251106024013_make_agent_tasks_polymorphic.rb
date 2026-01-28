# frozen_string_literal: true

class MakeAgentTasksPolymorphic < ActiveRecord::Migration[7.0]
  def change
    # Add polymorphic columns
    add_column :agent_tasks, :taskable_type, :string
    add_column :agent_tasks, :taskable_id, :bigint

    # Make goal_id nullable
    change_column_null :agent_tasks, :goal_id, true

    # Add index for polymorphic lookup
    add_index :agent_tasks, [:taskable_type, :taskable_id]

    # Backfill existing tasks to use polymorphic association
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE agent_tasks
          SET taskable_type = 'Goal', taskable_id = goal_id
          WHERE goal_id IS NOT NULL
        SQL
      end
    end
  end
end
