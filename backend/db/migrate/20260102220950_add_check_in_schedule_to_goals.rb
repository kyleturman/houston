# frozen_string_literal: true

class AddCheckInScheduleToGoals < ActiveRecord::Migration[7.1]
  def up
    # Add check_in_schedule column for recurring check-ins
    # Structure: { frequency: "daily", time: "09:00", day_of_week: nil, intent: "..." }
    add_column :goals, :check_in_schedule, :jsonb

    # Migrate existing short_term/long_term check-ins to next_follow_up
    Goal.find_each do |goal|
      next unless goal.runtime_state&.dig('check_ins')

      check_ins = goal.runtime_state['check_ins']
      new_state = goal.runtime_state.dup

      # Migrate short_term to next_follow_up (drop source field)
      if check_ins['short_term'].present?
        short_term = check_ins['short_term']
        new_state['next_follow_up'] = {
          'job_id' => short_term['job_id'],
          'scheduled_for' => short_term['scheduled_for'],
          'intent' => short_term['intent'],
          'created_at' => short_term['created_at']
        }
      end

      # Remove old check_ins structure
      new_state.delete('check_ins')

      goal.update_column(:runtime_state, new_state)
    end
  end

  def down
    # Migrate next_follow_up back to short_term
    Goal.find_each do |goal|
      next unless goal.runtime_state&.dig('next_follow_up')

      follow_up = goal.runtime_state['next_follow_up']
      new_state = goal.runtime_state.dup

      new_state['check_ins'] = {
        'short_term' => {
          'job_id' => follow_up['job_id'],
          'scheduled_for' => follow_up['scheduled_for'],
          'intent' => follow_up['intent'],
          'source' => 'agent',
          'created_at' => follow_up['created_at']
        }
      }

      new_state.delete('next_follow_up')
      goal.update_column(:runtime_state, new_state)
    end

    remove_column :goals, :check_in_schedule
  end
end
