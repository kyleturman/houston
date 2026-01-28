class CleanupFeedArchitecture < ActiveRecord::Migration[7.0]
  def change
    # Drop old feed tables (no longer needed)
    drop_table :feed_items, if_exists: true
    drop_table :feeds, if_exists: true

    # Add display_order for weighted randomization
    # FeedInsights always have display_order (null: false)
    add_column :feed_insights, :display_order, :integer, null: false, default: 0

    # Notes optionally have display_order (only agent-created notes)
    add_column :notes, :display_order, :integer

    # Add indexes for efficient sorting
    add_index :feed_insights, :display_order
    add_index :notes, :display_order

    # Backfill existing feed insights with basic ordering
    # (minutes since midnight of creation date)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE feed_insights
          SET display_order = EXTRACT(EPOCH FROM (created_at - DATE_TRUNC('day', created_at)))::integer / 60
          WHERE display_order = 0
        SQL
      end
    end
  end
end
