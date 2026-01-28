# frozen_string_literal: true

class CreateAgentActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_activities do |t|
      # Polymorphic association to agentable (Goal, AgentTask, UserAgent)
      t.references :agentable, polymorphic: true, null: false, index: true

      # Optional direct reference to goal for quick filtering
      t.references :goal, null: true, foreign_key: true, index: true

      # Agent metadata
      t.string :agent_type, null: false, index: true

      # Token and cost tracking
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cost_cents, null: false, default: 0

      # Tools usage
      t.jsonb :tools_called, null: false, default: []
      t.integer :tool_count, null: false, default: 0

      # Execution metadata
      t.datetime :started_at, null: false, index: true
      t.datetime :completed_at, null: false, index: true
      t.integer :iterations, null: false, default: 1
      t.boolean :natural_completion, null: false, default: false

      t.timestamps
    end

    # Composite indexes for common queries
    add_index :agent_activities, [:agentable_type, :agentable_id, :completed_at]
    add_index :agent_activities, [:goal_id, :completed_at]
    add_index :agent_activities, [:agent_type, :completed_at]
  end
end
