# frozen_string_literal: true

class AddKeywordHashesToNotes < ActiveRecord::Migration[8.0]
  def change
    add_column :notes, :keyword_hashes, :text, array: true, default: [], null: false
    add_index :notes, :keyword_hashes, using: :gin
  end
end
