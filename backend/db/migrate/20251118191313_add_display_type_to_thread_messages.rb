class AddDisplayTypeToThreadMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :thread_messages, :display_type, :integer, default: 0, null: false
  end
end
