class AddToolActivityIdToThreadMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :thread_messages, :tool_activity_id, :string
    add_index :thread_messages, :tool_activity_id
  end
end
