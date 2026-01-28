class AllowNullContentForUrlNotes < ActiveRecord::Migration[8.0]
  def change
    change_column_null :notes, :content, true
  end
end
