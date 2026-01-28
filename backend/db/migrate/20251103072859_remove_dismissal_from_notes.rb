class RemoveDismissalFromNotes < ActiveRecord::Migration[8.0]
  def change
    remove_column :notes, :dismissed_at, :datetime
    remove_column :notes, :dismissed_by_user_id, :integer
  end
end
