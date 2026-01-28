# frozen_string_literal: true

class CreateFeedInsights < ActiveRecord::Migration[7.0]
  def change
    create_table :feed_insights do |t|
      t.references :user, null: false, foreign_key: true
      t.references :user_agent, null: false, foreign_key: true
      t.integer :insight_type, null: false, default: 0  # 0=reflection, 1=discovery
      t.integer :goal_ids, array: true, default: []
      t.text :metadata  # Encrypted JSONB for content (reflections: prompt, discoveries: title/summary/url/source)

      t.timestamps
    end

    add_index :feed_insights, :insight_type
    add_index :feed_insights, :created_at
    add_index :feed_insights, [:user_id, :created_at]
  end
end
