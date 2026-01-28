# frozen_string_literal: true

class CreateNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :notes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :goal, null: false, foreign_key: true
      t.text :content, null: false
      t.text :description
      t.jsonb :metadata, null: false, default: {}
      t.integer :source, null: false, default: 0
      t.timestamps
    end

    add_index :notes, :source
    add_index :notes, [:user_id, :goal_id]
  end
end
