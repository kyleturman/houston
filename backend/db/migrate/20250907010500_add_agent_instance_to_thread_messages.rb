# frozen_string_literal: true

class AddAgentInstanceToThreadMessages < ActiveRecord::Migration[7.1]
  def change
    add_reference :thread_messages, :agent_instance, null: true, foreign_key: true
    add_index :thread_messages, [:agent_instance_id, :created_at]
  end
end
