# frozen_string_literal: true

class CreateAgentHistories < ActiveRecord::Migration[7.0]
  def change
    create_table :agent_histories do |t|
      # Polymorphic association to agentable (Goal, AgentTask, UserAgent)
      t.references :agentable, polymorphic: true, null: false, index: true

      # Core data - naming matches llm_history
      t.jsonb :agent_history, null: false, default: []
      t.text :summary, null: false

      # Metadata
      t.string :completion_reason  # 'feed_generation_complete', 'session_timeout', 'natural_stop'
      t.integer :message_count
      t.integer :token_count
      t.datetime :started_at
      t.datetime :completed_at, null: false

      t.timestamps

      # Indexes for efficient queries
      t.index [:agentable_type, :agentable_id, :completed_at],
        name: 'index_agent_histories_on_agentable_and_date'
      t.index :completed_at

      # GIN index for searchable JSON content
      t.index :agent_history, using: :gin, name: 'index_agent_histories_on_history_content'
    end
  end
end
