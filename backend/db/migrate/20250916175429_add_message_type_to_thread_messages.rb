class AddMessageTypeToThreadMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :thread_messages, :message_type, :integer, default: 0, null: false
    add_index :thread_messages, :message_type
  end
end
