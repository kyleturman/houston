class AddCacheTokensToLlmCosts < ActiveRecord::Migration[8.0]
  def change
    add_column :llm_costs, :cache_creation_input_tokens, :integer, default: 0, null: false
    add_column :llm_costs, :cache_read_input_tokens, :integer, default: 0, null: false
    add_column :llm_costs, :cached_tokens, :integer, default: 0, null: false
  end
end
