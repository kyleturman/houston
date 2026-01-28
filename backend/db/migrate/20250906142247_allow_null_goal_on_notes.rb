# frozen_string_literal: true

class AllowNullGoalOnNotes < ActiveRecord::Migration[8.0]
  def change
    change_column_null :notes, :goal_id, true
  end
end
