class UpdateGoalStatusEnum < ActiveRecord::Migration[8.0]
  def change
    # Add new status values to the enum
    # Current: active(0), paused(1), completed(2)
    # New: working(0), waiting(1), archived(2)
    
    # First, update existing data to match new semantics
    execute <<-SQL
      UPDATE goals 
      SET status = CASE 
        WHEN status = 0 THEN 1  -- active -> waiting (goals start waiting for user input)
        WHEN status = 1 THEN 1  -- paused -> waiting (paused goals become waiting)
        WHEN status = 2 THEN 2  -- completed -> archived (completed goals become archived)
      END
    SQL
    
    # The enum values will be updated in the model
  end
end
