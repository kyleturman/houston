# frozen_string_literal: true

class AddNoteTypeToNotes < ActiveRecord::Migration[8.0]
  def change
    add_column :notes, :note_type, :integer, null: false, default: 0
    add_index :notes, :note_type
  end
end
