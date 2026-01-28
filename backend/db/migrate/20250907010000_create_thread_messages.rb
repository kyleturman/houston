# frozen_string_literal: true

class CreateThreadMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :thread_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.references :goal, null: true, foreign_key: true
      t.references :agent_task, null: true, foreign_key: true

      t.integer :source, null: false, default: 0 # { user: 0, agent: 1, system: 2 }
      t.text :content, null: false

      t.jsonb :metadata, null: false, default: {}
      t.boolean :processed, null: false, default: false

      t.timestamps
    end

    add_index :thread_messages, [:user_id, :goal_id, :created_at]
    add_index :thread_messages, [:user_id, :agent_task_id, :created_at], name: 'index_thread_messages_on_user_and_task_and_created_at'
  end
end
