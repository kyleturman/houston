# frozen_string_literal: true

class SimplifyThreadsAndLogs < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Backfill agent_instance_id for any existing rows that are missing it (best-effort)
    say_with_time "Backfilling agent_instance_id on thread_messages" do
      ThreadMessage.where(agent_instance_id: nil).find_in_batches(batch_size: 500) do |batch|
        batch.each do |tm|
          ai = find_agent_instance_for(tm.user_id, tm[:goal_id], tm[:agent_task_id])
          if ai
            tm.update_columns(agent_instance_id: ai.id)
          end
        end
      end
    end

    say_with_time "Backfilling agent_instance_id on agent_activity_logs" do
      AgentActivityLog.where(agent_instance_id: nil).find_in_batches(batch_size: 500) do |batch|
        batch.each do |al|
          ai = find_agent_instance_for(al.user_id, al[:goal_id], al[:agent_task_id])
          if ai
            al.update_columns(agent_instance_id: ai.id)
          end
        end
      end
    end

    # Remove legacy indexes if they exist
    remove_index :thread_messages, [:user_id, :goal_id, :created_at] if index_exists?(:thread_messages, [:user_id, :goal_id, :created_at])
    remove_index :thread_messages, :goal_id if index_exists?(:thread_messages, :goal_id)
    remove_index :thread_messages, :agent_task_id if index_exists?(:thread_messages, :agent_task_id)

    remove_index :agent_activity_logs, :goal_id if index_exists?(:agent_activity_logs, :goal_id)
    remove_index :agent_activity_logs, [:agent_task_id, :created_at] if index_exists?(:agent_activity_logs, [:agent_task_id, :created_at])
    remove_index :agent_activity_logs, :agent_task_id if index_exists?(:agent_activity_logs, :agent_task_id)

    # Enforce NOT NULL on agent_instance_id
    change_column_null :thread_messages, :agent_instance_id, false
    change_column_null :agent_activity_logs, :agent_instance_id, false

    # Drop legacy foreign keys and columns
    remove_foreign_key :thread_messages, :goals if foreign_key_exists?(:thread_messages, :goals)
    remove_foreign_key :thread_messages, :agent_tasks if foreign_key_exists?(:thread_messages, :agent_tasks)
    remove_column :thread_messages, :goal_id, :bigint, if_exists: true
    remove_column :thread_messages, :agent_task_id, :bigint, if_exists: true

    remove_foreign_key :agent_activity_logs, :goals if foreign_key_exists?(:agent_activity_logs, :goals)
    remove_foreign_key :agent_activity_logs, :agent_tasks if foreign_key_exists?(:agent_activity_logs, :agent_tasks)
    remove_column :agent_activity_logs, :goal_id, :bigint, if_exists: true
    remove_column :agent_activity_logs, :agent_task_id, :bigint, if_exists: true

    # Ensure helpful indexes
    add_index :thread_messages, [:agent_instance_id, :created_at], algorithm: :concurrently unless index_exists?(:thread_messages, [:agent_instance_id, :created_at])
    add_index :agent_activity_logs, [:agent_instance_id, :created_at], algorithm: :concurrently unless index_exists?(:agent_activity_logs, [:agent_instance_id, :created_at])
  end

  def down
    add_column :thread_messages, :goal_id, :bigint
    add_column :thread_messages, :agent_task_id, :bigint
    add_column :agent_activity_logs, :goal_id, :bigint
    add_column :agent_activity_logs, :agent_task_id, :bigint

    add_foreign_key :thread_messages, :goals
    add_foreign_key :thread_messages, :agent_tasks
    add_foreign_key :agent_activity_logs, :goals
    add_foreign_key :agent_activity_logs, :agent_tasks

    add_index :thread_messages, [:user_id, :goal_id, :created_at] unless index_exists?(:thread_messages, [:user_id, :goal_id, :created_at])
    add_index :thread_messages, :goal_id unless index_exists?(:thread_messages, :goal_id)
    add_index :thread_messages, :agent_task_id unless index_exists?(:thread_messages, :agent_task_id)

    add_index :agent_activity_logs, :goal_id unless index_exists?(:agent_activity_logs, :goal_id)
    add_index :agent_activity_logs, [:agent_task_id, :created_at] unless index_exists?(:agent_activity_logs, [:agent_task_id, :created_at])
    add_index :agent_activity_logs, :agent_task_id unless index_exists?(:agent_activity_logs, :agent_task_id)

    change_column_null :thread_messages, :agent_instance_id, true
    change_column_null :agent_activity_logs, :agent_instance_id, true
  end

  private

  def find_agent_instance_for(user_id, goal_id, agent_task_id)
    scope = AgentInstance.where(user_id: user_id)
    if agent_task_id.present?
      scope.where(agent_task_id: agent_task_id, agent_type: :task).order(updated_at: :desc).first
    elsif goal_id.present?
      scope.where(goal_id: goal_id, agent_type: :goal).order(updated_at: :desc).first
    else
      nil
    end
  end
end
