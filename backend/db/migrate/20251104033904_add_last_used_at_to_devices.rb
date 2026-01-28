class AddLastUsedAtToDevices < ActiveRecord::Migration[8.0]
  def change
    add_column :devices, :last_used_at, :datetime
  end
end
