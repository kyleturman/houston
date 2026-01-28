# frozen_string_literal: true

class DropGinIndexesOnEncryptedFields < ActiveRecord::Migration[8.0]
  def up
    # Drop GIN indexes on fields that will be encrypted
    # Encrypted fields cannot be searched via GIN indexes
    remove_index :goals, name: 'index_goals_on_llm_history', if_exists: true
    remove_index :agent_tasks, name: 'index_agent_tasks_on_llm_history', if_exists: true
    remove_index :user_agents, name: 'index_user_agents_on_llm_history', if_exists: true
    remove_index :agent_histories, name: 'index_agent_histories_on_history_content', if_exists: true
  end

  def down
    # Recreate indexes if migration is rolled back
    add_index :goals, :llm_history, using: :gin, name: 'index_goals_on_llm_history', if_not_exists: true
    add_index :agent_tasks, :llm_history, using: :gin, name: 'index_agent_tasks_on_llm_history', if_not_exists: true
    add_index :user_agents, :llm_history, using: :gin, name: 'index_user_agents_on_llm_history', if_not_exists: true
    add_index :agent_histories, :agent_history, using: :gin, name: 'index_agent_histories_on_history_content', if_not_exists: true
  end
end
