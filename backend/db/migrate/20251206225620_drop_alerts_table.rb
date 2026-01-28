# frozen_string_literal: true

class DropAlertsTable < ActiveRecord::Migration[8.0]
  def up
    drop_table :alerts, if_exists: true
  end

  def down
    create_table :alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :goal, foreign_key: true
      t.string :title, null: false
      t.text :content, null: false
      t.datetime :expires_at, null: false
      t.integer :status, default: 0

      t.timestamps
    end

    add_index :alerts, [:user_id, :status]
    add_index :alerts, :expires_at
  end
end
