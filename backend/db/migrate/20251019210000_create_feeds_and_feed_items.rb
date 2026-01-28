# frozen_string_literal: true

class CreateFeedsAndFeedItems < ActiveRecord::Migration[7.1]
  def change
    create_table :feeds do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :generated_at, null: false
      t.integer :generation_duration_seconds, null: false
      t.timestamps
    end

    create_table :feed_items do |t|
      t.references :feed, null: false, foreign_key: true
      t.string :item_type, null: false
      
      # For reference items (notes, alerts)
      t.references :referenceable, polymorphic: true, null: true
      
      # For inline items (reflections, discoveries)
      t.jsonb :content, default: {}, null: false
      
      t.integer :position, null: false
      t.timestamps
    end

    add_index :feed_items, [:feed_id, :position]
    add_index :feed_items, :item_type
  end
end
