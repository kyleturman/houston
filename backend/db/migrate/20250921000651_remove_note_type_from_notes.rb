class RemoveNoteTypeFromNotes < ActiveRecord::Migration[8.0]
  def change
    remove_index :notes, :note_type
    remove_column :notes, :note_type, :integer
  end
end
