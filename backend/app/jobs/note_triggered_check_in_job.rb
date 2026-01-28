# frozen_string_literal: true

# Job to ensure agent reviews notes within a reasonable time
#
# When a user adds a note to a goal, this job evaluates whether a follow-up
# needs to be scheduled or pulled closer. This creates the feeling of
# an agent that's paying attention to what you write.
#
# Key behaviors:
#   - Uses debouncing to avoid rescheduling on rapid successive notes
#   - Respects existing schedules (if scheduled check-in is soon, skip)
#   - Creates or updates next_follow_up slot
#
# Usage:
#   NoteTriggeredCheckInJob.perform_in(5.seconds, goal_id)
#
class NoteTriggeredCheckInJob
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  def perform(goal_id)
    goal = Goal.find_by(id: goal_id)
    return unless goal&.active?

    # Skip if we adjusted recently (debounce multiple rapid notes)
    if recently_adjusted?(goal)
      Rails.logger.debug("[NoteTriggeredCheckInJob] Skipping Goal##{goal_id} - recently adjusted")
      return
    end

    # If goal has a schedule with check-in coming soon, skip the follow-up
    if goal.has_check_in_schedule?
      calculator = Goals::ScheduleCalculator.new(goal)
      hours_until = calculator.hours_until_next

      if hours_until && hours_until <= skip_if_scheduled_within_hours
        Rails.logger.debug("[NoteTriggeredCheckInJob] Skipping Goal##{goal_id} - scheduled check-in in #{hours_until.round(1)}h")
        return
      end
    end

    target_time = note_triggered_delay.from_now
    current_follow_up = goal.next_follow_up

    if current_follow_up
      scheduled_for = Time.parse(current_follow_up['scheduled_for'])

      # If follow-up is more than target time away, pull it closer and store original
      if scheduled_for > target_time
        Rails.logger.info("[NoteTriggeredCheckInJob] Pulling follow-up closer for Goal##{goal_id}, storing original")
        store_original_follow_up(goal, current_follow_up)
        reschedule_follow_up(goal, target_time, current_follow_up)
      else
        Rails.logger.debug("[NoteTriggeredCheckInJob] Follow-up already soon enough for Goal##{goal_id}")
      end
    else
      # No follow-up exists - create one
      Rails.logger.info("[NoteTriggeredCheckInJob] Creating note-triggered follow-up for Goal##{goal_id}")
      create_follow_up(goal, target_time)
    end

    # Mark adjustment time for debouncing
    update_adjustment_timestamp(goal)
  end

  private

  def note_triggered_delay
    Agents::Constants::NOTE_TRIGGERED_DELAY_MINUTES.minutes
  end

  def skip_if_scheduled_within_hours
    Agents::Constants::NOTE_TRIGGERED_SKIP_IF_SCHEDULED_WITHIN_HOURS
  end

  def debounce_window
    Agents::Constants::NOTE_TRIGGERED_DEBOUNCE_MINUTES.minutes
  end

  def recently_adjusted?(goal)
    last_adjusted = goal.check_in_last_adjusted_at
    return false unless last_adjusted

    Time.parse(last_adjusted) > debounce_window.ago
  end

  def store_original_follow_up(goal, current_follow_up)
    goal.set_original_follow_up!({
      'scheduled_for' => current_follow_up['scheduled_for'],
      'intent' => current_follow_up['intent'],
      'stored_at' => Time.current.iso8601
    })
  end

  def reschedule_follow_up(goal, new_time, current_follow_up)
    # Cancel old job
    begin
      Jobs::Scheduler.cancel(current_follow_up['job_id'])
    rescue => e
      Rails.logger.warn("[NoteTriggeredCheckInJob] Could not cancel old job: #{e.message}")
    end

    # Use time before the note was created to ensure it's included in "recent notes" query.
    # The job runs ~5 seconds after note creation, so 1 minute ago safely captures the note.
    reference_time = 1.minute.ago.iso8601

    # Build check-in data with original follow-up info
    check_in_data = {
      'intent' => 'Review recent notes',
      'source' => 'note_triggered',
      'created_at' => reference_time,
      'notes_since' => reference_time,
      'original_follow_up' => {
        'scheduled_for' => current_follow_up['scheduled_for'],
        'intent' => current_follow_up['intent']
      }
    }

    # Schedule new job
    job_id = AgentCheckInJob.perform_at(
      new_time,
      'Goal',
      goal.id,
      'follow_up',
      check_in_data
    )

    # Update next_follow_up
    goal.set_next_follow_up!({
      'job_id' => job_id,
      'scheduled_for' => new_time.iso8601,
      'intent' => 'Review recent notes',
      'created_at' => reference_time
    })

    publish_goal_updated(goal)
  end

  def create_follow_up(goal, scheduled_time)
    # Use time before the note was created to ensure it's included in "recent notes" query.
    reference_time = 1.minute.ago.iso8601

    check_in_data = {
      'intent' => 'Review recent notes',
      'source' => 'note_triggered',
      'created_at' => reference_time,
      'notes_since' => reference_time
    }

    job_id = AgentCheckInJob.perform_at(
      scheduled_time,
      'Goal',
      goal.id,
      'follow_up',
      check_in_data
    )

    goal.set_next_follow_up!({
      'job_id' => job_id,
      'scheduled_for' => scheduled_time.iso8601,
      'intent' => 'Review recent notes',
      'created_at' => reference_time
    })

    publish_goal_updated(goal)
  end

  def update_adjustment_timestamp(goal)
    goal.set_check_in_last_adjusted_at!
  end

  def publish_goal_updated(goal)
    # Build next check-in info
    next_check_in = nil
    candidates = []

    if (scheduled = goal.scheduled_check_in)
      candidates << {
        type: 'scheduled',
        scheduled_for: scheduled['scheduled_for'],
        intent: scheduled['intent']
      }
    end

    if (follow_up = goal.next_follow_up)
      candidates << {
        type: 'follow_up',
        scheduled_for: follow_up['scheduled_for'],
        intent: follow_up['intent']
      }
    end

    next_check_in = candidates.min_by { |c| Time.parse(c[:scheduled_for]) } if candidates.any?

    channel = Streams::Channels.global_for_user(user: goal.user)
    Streams::Broker.publish(
      channel,
      event: 'goal_updated',
      data: {
        goal_id: goal.id,
        title: goal.title,
        status: goal.status,
        updated_at: Time.current.iso8601,
        next_check_in: next_check_in,
        check_in_schedule: goal.check_in_schedule
      }
    )
  end
end
