# frozen_string_literal: true

class DropAgentInstancesAndReferences < ActiveRecord::Migration[8.0]
  def up
    # Remove foreign key and column from thread_messages to agent_instances, if present
    if foreign_key_exists?(:thread_messages, :agent_instances)
      remove_foreign_key :thread_messages, :agent_instances
    end
    if column_exists?(:thread_messages, :agent_instance_id)
      begin
        remove_index :thread_messages, name: "index_thread_messages_on_agent_instance_id_and_created_at"
      rescue StandardError
        # ignore if index missing
      end
      begin
        remove_index :thread_messages, :agent_instance_id
      rescue StandardError
        # ignore if index missing
      end
      remove_column :thread_messages, :agent_instance_id
    end

    # Remove foreign key and column from agent_activity_logs to agent_instances, if present
    if foreign_key_exists?(:agent_activity_logs, :agent_instances)
      remove_foreign_key :agent_activity_logs, :agent_instances
    end
    if column_exists?(:agent_activity_logs, :agent_instance_id)
      begin
        remove_index :agent_activity_logs, name: "index_activity_logs_on_agent_instance_and_created_at"
      rescue StandardError
        # ignore if index missing
      end
      begin
        remove_index :agent_activity_logs, :agent_instance_id
      rescue StandardError
        # ignore if index missing
      end
      remove_column :agent_activity_logs, :agent_instance_id
    end

    # Drop the agent_instances table if it exists
    if table_exists?(:agent_instances)
      begin
        remove_foreign_key :agent_instances, :users
      rescue StandardError
      end
      begin
        remove_foreign_key :agent_instances, :goals
      rescue StandardError
      end
      begin
        remove_foreign_key :agent_instances, :agent_tasks
      rescue StandardError
      end
      drop_table :agent_instances
    end
  end

  def down
    create_table :agent_instances do |t|
      t.bigint :user_id, null: false
      t.bigint :goal_id
      t.bigint :agent_task_id
      t.integer :agent_type, default: 0, null: false
      t.integer :status, default: 0, null: false
      t.string :orchestrator_job_id
      t.jsonb :state, default: {}, null: false
      t.timestamps
      t.jsonb :execution_plan, default: {}
      t.jsonb :learnings, default: []
      t.text :agent_memory
      t.jsonb :llm_history, default: []
    end

    add_index :agent_instances, :user_id
    add_index :agent_instances, :goal_id
    add_index :agent_instances, :agent_task_id
    add_index :agent_instances, :llm_history, using: :gin
    add_index :agent_instances, :orchestrator_job_id

    add_column :thread_messages, :agent_instance_id, :bigint
    add_index :thread_messages, [:agent_instance_id, :created_at], name: "index_thread_messages_on_agent_instance_id_and_created_at"
    add_index :thread_messages, :agent_instance_id

    add_column :agent_activity_logs, :agent_instance_id, :bigint
    add_index :agent_activity_logs, [:agent_instance_id, :created_at], name: "index_activity_logs_on_agent_instance_and_created_at"
    add_index :agent_activity_logs, :agent_instance_id

    add_foreign_key :agent_instances, :users
    add_foreign_key :agent_instances, :goals
    add_foreign_key :agent_instances, :agent_tasks
    add_foreign_key :thread_messages, :agent_instances
    add_foreign_key :agent_activity_logs, :agent_instances
  end
end
