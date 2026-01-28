class AddAccentColorToGoals < ActiveRecord::Migration[8.0]
  def change
    add_column :goals, :accent_color, :string
  end
end
