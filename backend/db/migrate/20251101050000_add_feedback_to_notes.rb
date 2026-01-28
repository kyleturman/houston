# frozen_string_literal: true

class AddFeedbackToNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :notes, :feedback_sentiment, :string
    add_column :notes, :feedback_text, :text
    add_column :notes, :feedback_processed, :boolean, default: false
    add_column :notes, :feedback_submitted_at, :datetime

    add_index :notes, :feedback_processed
  end
end
