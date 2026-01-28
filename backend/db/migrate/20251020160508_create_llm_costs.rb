class CreateLlmCosts < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_costs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :agentable, polymorphic: true, null: true
      t.string :provider, null: false
      t.string :model, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.decimal :cost, precision: 10, scale: 6, null: false, default: 0.0
      t.string :context

      t.timestamps
    end
    
    add_index :llm_costs, [:user_id, :created_at], if_not_exists: true
    add_index :llm_costs, [:agentable_type, :agentable_id, :created_at], name: 'index_llm_costs_on_agentable', if_not_exists: true
  end
end
