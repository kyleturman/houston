# frozen_string_literal: true

class AddLastProactiveCheckAtToGoals < ActiveRecord::Migration[7.1]
  def change
    add_column :goals, :last_proactive_check_at, :datetime
    add_index :goals, :last_proactive_check_at
  end
end
