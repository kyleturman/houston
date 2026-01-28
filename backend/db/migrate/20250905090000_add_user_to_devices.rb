# frozen_string_literal: true

class AddUserToDevices < ActiveRecord::Migration[8.0]
  def change
    add_reference :devices, :user, foreign_key: true, null: true
  end
end
