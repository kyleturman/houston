class RemoveDisplayTypeFromThreadMessages < ActiveRecord::Migration[8.0]
  def change
    remove_column :thread_messages, :display_type, :integer
  end
end
