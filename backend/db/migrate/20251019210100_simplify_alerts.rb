# frozen_string_literal: true

class SimplifyAlerts < ActiveRecord::Migration[7.1]
  def change
    remove_column :alerts, :priority, :integer if column_exists?(:alerts, :priority)
    remove_column :alerts, :action_url, :string if column_exists?(:alerts, :action_url)
  end
end
