# frozen_string_literal: true

class RemoveNotesContentTsv < ActiveRecord::Migration[8.0]
  def change
    remove_index :notes, :content_tsv if index_exists?(:notes, :content_tsv)
    remove_column :notes, :content_tsv, :tsvector if column_exists?(:notes, :content_tsv)
  end
end
