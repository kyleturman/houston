class AddAppIntentToNoteSource < ActiveRecord::Migration[8.0]
  def change
    # No schema change needed - the source column already exists as an integer
    # This migration documents the addition of app_intent: 4 to the enum mapping
    # Enum values: user: 0, agent: 1, import: 2, system: 3, app_intent: 4
  end
end
