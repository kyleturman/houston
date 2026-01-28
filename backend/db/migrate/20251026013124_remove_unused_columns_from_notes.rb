class RemoveUnusedColumnsFromNotes < ActiveRecord::Migration[8.0]
  def change
    # Remove unused description column (never populated, not used by agents or UI)
    remove_column :notes, :description, :text, if_exists: true

    # Remove unused keyword_hashes column (keyword search system never implemented)
    remove_column :notes, :keyword_hashes, :text, if_exists: true
  end
end
