# frozen_string_literal: true

module Goals
  # Calculates next check-in time based on a goal's check_in_schedule
  #
  # Schedule structure:
  #   {
  #     frequency: "daily" | "weekdays" | "weekly" | "none",
  #     time: "09:00",           # 24-hour format in user's timezone
  #     day_of_week: "monday",   # only for weekly frequency
  #     intent: "Review transactions"
  #   }
  #
  # Usage:
  #   calculator = Goals::ScheduleCalculator.new(goal)
  #   next_time = calculator.next_occurrence  # => Time object or nil
  #   calculator.schedule_next_check_in!      # => schedules the job
  #
  class ScheduleCalculator
    VALID_FREQUENCIES = %w[daily weekdays weekly none].freeze
    DAYS_OF_WEEK = %w[sunday monday tuesday wednesday thursday friday saturday].freeze

    def initialize(goal)
      @goal = goal
      @schedule = goal.check_in_schedule
      @user = goal.user
    end

    # Calculate the next occurrence based on schedule
    # Returns nil if no schedule or invalid
    def next_occurrence(from: Time.current)
      return nil unless valid_schedule?

      user_tz = ActiveSupport::TimeZone[@user.timezone_or_default]
      now_in_tz = from.in_time_zone(user_tz)
      target_time = parse_time_in_timezone(user_tz, now_in_tz.to_date)

      case @schedule['frequency']
      when 'daily'
        next_daily(now_in_tz, target_time)
      when 'weekdays'
        next_weekday(now_in_tz, target_time)
      when 'weekly'
        next_weekly(now_in_tz, target_time)
      end
    end

    # Schedule the next check-in job based on schedule
    # Returns the job_id or nil if no schedule
    def schedule_next_check_in!
      scheduled_time = next_occurrence
      return nil unless scheduled_time

      # Cancel existing scheduled check-in if present
      cancel_existing_scheduled_job!

      # Schedule new job
      job_id = AgentCheckInJob.perform_at(
        scheduled_time,
        'Goal',
        @goal.id,
        'scheduled', # slot indicator for scheduled vs follow-up
        {
          'intent' => @schedule['intent'] || 'Scheduled check-in',
          'created_at' => Time.current.iso8601
        }
      )

      # Store in runtime_state
      @goal.set_scheduled_check_in!({
        'job_id' => job_id,
        'scheduled_for' => scheduled_time.iso8601,
        'intent' => @schedule['intent'] || 'Scheduled check-in',
        'created_at' => Time.current.iso8601
      })

      Rails.logger.info("[ScheduleCalculator] Scheduled check-in for Goal##{@goal.id} at #{scheduled_time}")
      job_id
    end

    # Check if the schedule is valid
    def valid_schedule?
      return false if @schedule.blank?
      return false unless VALID_FREQUENCIES.include?(@schedule['frequency'])
      return false if @schedule['frequency'] == 'none'
      return false if @schedule['time'].blank?

      # Weekly requires day_of_week
      if @schedule['frequency'] == 'weekly'
        return false unless DAYS_OF_WEEK.include?(@schedule['day_of_week']&.downcase)
      end

      true
    end

    # Time until next scheduled check-in (in hours)
    def hours_until_next
      next_time = next_occurrence
      return nil unless next_time
      ((next_time - Time.current) / 1.hour).round(1)
    end

    private

    def parse_time_in_timezone(user_tz, date)
      hour, minute = @schedule['time'].split(':').map(&:to_i)
      user_tz.local(date.year, date.month, date.day, hour, minute)
    end

    def next_daily(now, target_time)
      # If target time already passed today, schedule for tomorrow
      if target_time <= now
        target_time + 1.day
      else
        target_time
      end
    end

    def next_weekday(now, target_time)
      candidate = target_time

      # If already passed today, start from tomorrow
      candidate += 1.day if candidate <= now

      # Find next weekday (Mon-Fri = wday 1-5)
      while candidate.wday == 0 || candidate.wday == 6
        candidate += 1.day
      end

      candidate
    end

    def next_weekly(now, target_time)
      target_wday = DAYS_OF_WEEK.index(@schedule['day_of_week'].downcase)
      current_wday = now.wday

      # Calculate days until target day
      days_until = (target_wday - current_wday) % 7

      candidate = target_time + days_until.days

      # If same day but time passed, go to next week
      if candidate <= now
        candidate += 7.days
      end

      candidate
    end

    def cancel_existing_scheduled_job!
      existing = @goal.scheduled_check_in&.dig('job_id')
      return unless existing

      begin
        Jobs::Scheduler.cancel(existing)
      rescue => e
        Rails.logger.warn("[ScheduleCalculator] Could not cancel job #{existing}: #{e.message}")
      end
    end
  end
end
