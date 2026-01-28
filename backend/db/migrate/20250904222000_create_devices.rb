# frozen_string_literal: true

class CreateDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :devices do |t|
      t.string :name, null: false
      t.string :platform, null: false
      t.string :token_digest, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :devices, :platform
    add_index :devices, :created_at
  end
end
