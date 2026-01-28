class CreateUserAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :user_agents do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :llm_history, default: [], null: false
      t.jsonb :learnings, default: [], null: false
      t.jsonb :runtime_state, default: {}, null: false
      t.datetime :last_synthesis_at

      t.timestamps
    end

    # Add indexes for performance
    add_index :user_agents, :llm_history, using: :gin
    add_index :user_agents, :last_synthesis_at
  end
end
