class AddDisplayOrderToGoals < ActiveRecord::Migration[8.0]
  def change
    add_column :goals, :display_order, :integer, default: 0, null: false
    add_index :goals, [:user_id, :display_order]

    # Set initial order based on created_at for existing goals
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE goals
          SET display_order = subquery.row_number
          FROM (
            SELECT id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at) - 1 as row_number
            FROM goals
          ) AS subquery
          WHERE goals.id = subquery.id
        SQL
      end
    end
  end
end
