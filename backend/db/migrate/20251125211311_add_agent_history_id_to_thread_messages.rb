class AddAgentHistoryIdToThreadMessages < ActiveRecord::Migration[8.0]
  def change
    add_reference :thread_messages, :agent_history,
      null: true,
      foreign_key: { on_delete: :cascade },
      index: true
  end
end
