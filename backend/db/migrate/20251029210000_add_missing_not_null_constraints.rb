# frozen_string_literal: true

class AddMissingNotNullConstraints < ActiveRecord::Migration[7.0]
  def up
    # Devices must always belong to a user
    # First, clean up any orphaned devices (shouldn't exist, but just in case)
    execute "DELETE FROM devices WHERE user_id IS NULL"
    change_column_null :devices, :user_id, false
  end

  def down
    change_column_null :devices, :user_id, true
  end
end
