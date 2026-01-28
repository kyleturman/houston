# frozen_string_literal: true

class AddDismissalToNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :notes, :dismissed_at, :datetime
    add_column :notes, :dismissed_by_user_id, :integer

    add_index :notes, :dismissed_at
    add_index :notes, :dismissed_by_user_id
  end
end
