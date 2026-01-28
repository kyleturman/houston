class AddTimePeriodToFeedInsights < ActiveRecord::Migration[8.0]
  def change
    add_column :feed_insights, :time_period, :string

    # Backfill existing records based on created_at hour
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE feed_insights
          SET time_period = CASE
            WHEN EXTRACT(HOUR FROM created_at) < 12 THEN 'morning'
            WHEN EXTRACT(HOUR FROM created_at) < 17 THEN 'afternoon'
            ELSE 'evening'
          END
          WHERE time_period IS NULL
        SQL
      end
    end
  end
end
