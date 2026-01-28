# frozen_string_literal: true

class AddUniqueActiveAgentInstanceIndexes < ActiveRecord::Migration[7.1]
  def change
    # Only one active goal-type agent per goal
    add_index :agent_instances,
              [:goal_id, :agent_type, :status],
              unique: true,
              where: "goal_id IS NOT NULL AND agent_type = 0 AND status = 0",
              name: "index_unique_active_goal_agent_instance"

    # Only one active task-type agent per task
    add_index :agent_instances,
              [:agent_task_id, :agent_type, :status],
              unique: true,
              where: "agent_task_id IS NOT NULL AND agent_type = 1 AND status = 0",
              name: "index_unique_active_task_agent_instance"
  end
end
