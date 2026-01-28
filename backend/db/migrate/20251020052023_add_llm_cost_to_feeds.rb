class AddLlmCostToFeeds < ActiveRecord::Migration[8.0]
  def change
    add_column :feeds, :llm_cost, :decimal, precision: 10, scale: 6, default: 0.0, null: false
  end
end
