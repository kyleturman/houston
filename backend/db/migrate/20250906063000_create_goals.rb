# frozen_string_literal: true

class CreateGoals < ActiveRecord::Migration[8.0]
  def change
    create_table :goals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    add_index :goals, :status
    add_index :goals, [:user_id, :status]
  end
end
