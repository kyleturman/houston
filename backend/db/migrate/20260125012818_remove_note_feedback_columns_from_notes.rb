class RemoveNoteFeedbackColumnsFromNotes < ActiveRecord::Migration[8.0]
  def change
    # Remove the index first (must be done before dropping the column)
    remove_index :notes, :feedback_processed, if_exists: true

    # Remove feedback columns
    remove_column :notes, :feedback_sentiment, :string
    remove_column :notes, :feedback_text, :text
    remove_column :notes, :feedback_processed, :boolean
    remove_column :notes, :feedback_submitted_at, :datetime
  end
end
