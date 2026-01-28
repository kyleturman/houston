# frozen_string_literal: true

class AddAgentInstanceToAgentActivityLogs < ActiveRecord::Migration[7.1]
  def change
    add_reference :agent_activity_logs, :agent_instance, null: true, foreign_key: true
    add_index :agent_activity_logs, [:agent_instance_id, :created_at], name: 'index_activity_logs_on_agent_instance_and_created_at'
  end
end
