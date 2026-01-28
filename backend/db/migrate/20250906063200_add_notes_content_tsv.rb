# frozen_string_literal: true

class AddNotesContentTsv < ActiveRecord::Migration[8.0]
  def change
    add_column :notes, :content_tsv, :tsvector
    add_index :notes, :content_tsv, using: :gin
  end
end
