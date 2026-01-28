# frozen_string_literal: true

class AddTokenIdToDevices < ActiveRecord::Migration[8.0]
  def up
    add_column :devices, :token_id, :string

    # Backfill existing rows with random token_id
    say_with_time "Backfilling devices.token_id" do
      Device.reset_column_information
      Device.find_each do |d|
        d.update_columns(token_id: SecureRandom.hex(8))
      end
    end

    change_column_null :devices, :token_id, false
    add_index :devices, :token_id, unique: true
  end

  def down
    remove_index :devices, :token_id
    remove_column :devices, :token_id
  end
end
