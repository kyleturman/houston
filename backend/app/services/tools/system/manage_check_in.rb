# frozen_string_literal: true

module Tools
  module System
    class ManageCheckIn < BaseTool
      # Tool metadata for planning and orchestration
      def self.metadata
        super.merge(
          name: 'manage_check_in',
          description: 'Manage check-ins for this goal. Use set_schedule for recurring check-ins (daily, weekdays, weekly). Use schedule_follow_up for one-time contextual follow-ups. Use clear to remove. [Visible - user sees confirmation message]',
          params_hint: 'action (set_schedule/schedule_follow_up/clear_follow_up/clear_schedule), frequency, time, day_of_week, delay, intent',
          is_user_facing: true
        )
      end

      # JSON Schema for tool parameters
      def self.schema
        {
          type: 'object',
          properties: {
            action: {
              type: 'string',
              enum: ['set_schedule', 'schedule_follow_up', 'clear_follow_up', 'clear_schedule'],
              description: 'set_schedule for recurring (daily/weekly), schedule_follow_up for one-time, clear_follow_up/clear_schedule to remove'
            },
            frequency: {
              type: 'string',
              enum: ['daily', 'weekdays', 'weekly', 'none'],
              description: 'For set_schedule: how often to check in'
            },
            time: {
              type: 'string',
              description: 'For set_schedule: time of day (e.g., "9:00", "09:00", "5am", "14:30")'
            },
            day_of_week: {
              type: 'string',
              enum: ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'],
              description: 'For weekly schedule: which day'
            },
            delay: {
              type: 'string',
              description: 'For schedule_follow_up: when to follow up (e.g., "3 hours", "2 days", "tomorrow 9am")'
            },
            intent: {
              type: 'string',
              description: 'Why you\'re checking in (e.g., "Review transactions", "Follow up on flight research")'
            }
          },
          required: ['action'],
          additionalProperties: false
        }
      end

      # Execute the tool
      def execute(action:, frequency: nil, time: nil, day_of_week: nil, delay: nil, intent: nil)
        # Validate goal agent only
        unless @agentable.goal?
          return { success: false, error: 'Only goal agents can manage check-ins' }
        end

        case action.to_s.downcase
        when 'set_schedule'
          handle_set_schedule(frequency, time, day_of_week, intent)
        when 'schedule_follow_up'
          handle_schedule_follow_up(delay, intent)
        when 'clear_follow_up'
          handle_clear_follow_up
        when 'clear_schedule'
          handle_clear_schedule
        else
          { success: false, error: 'Action must be set_schedule, schedule_follow_up, clear_follow_up, or clear_schedule' }
        end
      end

      private

      def handle_set_schedule(frequency, time, day_of_week, intent)
        return { success: false, error: 'frequency is required for set_schedule' } if frequency.blank?
        return { success: false, error: 'time is required for set_schedule' } if time.blank?
        return { success: false, error: 'intent is required for set_schedule' } if intent.blank?

        unless %w[daily weekdays weekly none].include?(frequency)
          return { success: false, error: 'frequency must be daily, weekdays, weekly, or none' }
        end

        if frequency == 'weekly' && day_of_week.blank?
          return { success: false, error: 'day_of_week is required for weekly schedule' }
        end

        # Normalize time to 24-hour format
        normalized_time = normalize_time(time)
        unless normalized_time
          return { success: false, error: 'Could not parse time. Use format like "9:00", "09:00", "5am", "14:30"' }
        end

        # Build schedule
        schedule = {
          'frequency' => frequency,
          'time' => normalized_time,
          'intent' => intent
        }
        schedule['day_of_week'] = day_of_week.downcase if day_of_week.present?

        # Save to goal
        @agentable.update!(check_in_schedule: schedule)

        # Schedule the next occurrence
        calculator = Goals::ScheduleCalculator.new(@agentable.reload)
        calculator.schedule_next_check_in!

        # Broadcast update
        publish_goal_updated

        # Build response
        schedule_description = case frequency
        when 'daily'
          "every day at #{format_time_for_display(normalized_time)}"
        when 'weekdays'
          "weekdays at #{format_time_for_display(normalized_time)}"
        when 'weekly'
          "every #{day_of_week.capitalize} at #{format_time_for_display(normalized_time)}"
        when 'none'
          "disabled"
        end

        {
          success: true,
          title: "I'll check in #{schedule_description}",
          observation: "Set recurring check-in schedule: #{schedule_description}. Intent: #{intent}"
        }
      end

      def handle_schedule_follow_up(delay, intent)
        return { success: false, error: 'delay is required for schedule_follow_up' } if delay.blank?
        return { success: false, error: 'intent is required for schedule_follow_up' } if intent.blank?

        # Check if schedule will handle this soon
        if @agentable.has_check_in_schedule?
          calculator = Goals::ScheduleCalculator.new(@agentable)
          hours_until = calculator.hours_until_next

          # If scheduled check-in is within 24 hours, suggest using that instead
          if hours_until && hours_until < 24
            # Parse the delay to see if follow-up would be after scheduled
            follow_up_time = parse_delay(delay)
            if follow_up_time
              scheduled_time = calculator.next_occurrence
              if scheduled_time && follow_up_time >= scheduled_time
                return {
                  success: false,
                  error: "Scheduled check-in is coming up in #{hours_until.round} hours. No need for a separate follow-up unless it's urgent."
                }
              end
            end
          end
        end

        # Parse delay
        scheduled_time = parse_delay(delay)
        unless scheduled_time
          return {
            success: false,
            error: 'Could not parse delay. Use format like "3 days", "1 week", "4 hours", "tomorrow 9am"'
          }
        end

        # Validate min/max
        hours_from_now = ((scheduled_time - Time.current) / 1.hour).round
        if hours_from_now < Agents::Constants::MIN_CHECK_IN_DELAY_HOURS
          return {
            success: false,
            error: "Follow-up must be at least #{Agents::Constants::MIN_CHECK_IN_DELAY_HOURS} hour away"
          }
        end

        days_from_now = hours_from_now / 24.0
        if days_from_now > Agents::Constants::MAX_CHECK_IN_DELAY_DAYS
          return {
            success: false,
            error: "Follow-up cannot be more than #{Agents::Constants::MAX_CHECK_IN_DELAY_DAYS} days away"
          }
        end

        # Cancel existing follow-up if present
        existing = @agentable.next_follow_up
        if existing.present?
          begin
            Jobs::Scheduler.cancel(existing['job_id'])
          rescue => e
            Rails.logger.warn("[ManageCheckIn] Could not cancel existing follow-up: #{e.message}")
          end
        end

        # Schedule new follow-up
        job_id = AgentCheckInJob.perform_at(
          scheduled_time,
          'Goal',
          @agentable.id,
          'follow_up',
          {
            'intent' => intent,
            'created_at' => Time.current.iso8601
          }
        )

        # Store in runtime_state
        @agentable.set_next_follow_up!({
          'job_id' => job_id,
          'scheduled_for' => scheduled_time.iso8601,
          'intent' => intent,
          'created_at' => Time.current.iso8601
        })

        # Broadcast update
        publish_goal_updated

        # Display time in user's timezone
        user_timezone = @user.timezone_or_default
        display_time = scheduled_time.in_time_zone(user_timezone)

        {
          success: true,
          title: friendly_follow_up_message(scheduled_time),
          observation: "Scheduled follow-up for #{display_time.strftime('%B %d at %I:%M %p')}: #{intent}"
        }
      end

      def handle_clear_follow_up
        existing = @agentable.next_follow_up
        return { success: false, error: 'No follow-up scheduled' } unless existing

        # Cancel Sidekiq job
        begin
          Jobs::Scheduler.cancel(existing['job_id'])
        rescue => e
          Rails.logger.warn("[ManageCheckIn] Could not cancel job: #{e.message}")
        end

        # Clear from runtime_state
        @agentable.clear_next_follow_up!

        # Broadcast update
        publish_goal_updated

        {
          success: true,
          title: "Cleared that follow-up",
          observation: "Cleared follow-up: #{existing['intent']}"
        }
      end

      def handle_clear_schedule
        unless @agentable.has_check_in_schedule?
          return { success: false, error: 'No recurring schedule set' }
        end

        old_schedule = @agentable.check_in_schedule

        # Cancel any scheduled job
        existing_job = @agentable.scheduled_check_in&.dig('job_id')
        if existing_job
          begin
            Jobs::Scheduler.cancel(existing_job)
          rescue => e
            Rails.logger.warn("[ManageCheckIn] Could not cancel scheduled job: #{e.message}")
          end
        end

        # Clear schedule and scheduled_check_in from runtime_state
        @agentable.update!(check_in_schedule: nil)
        @agentable.clear_scheduled_check_in!

        # Broadcast update
        publish_goal_updated

        {
          success: true,
          title: "Cleared the recurring schedule",
          observation: "Cleared recurring #{old_schedule['frequency']} check-in schedule"
        }
      end

      def normalize_time(time_string)
        cleaned = time_string.to_s.downcase.strip

        # Handle formats like "5am", "5 am", "5:00am", "5:00 am"
        if (match = cleaned.match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/i))
          hour = match[1].to_i
          minutes = match[2]&.to_i || 0
          meridiem = match[3]&.downcase

          if meridiem == 'pm' && hour < 12
            hour += 12
          elsif meridiem == 'am' && hour == 12
            hour = 0
          end

          return format('%02d:%02d', hour, minutes)
        end

        # Handle 24-hour format like "14:30", "09:00"
        if cleaned.match?(/^\d{1,2}:\d{2}$/)
          parts = cleaned.split(':')
          hour = parts[0].to_i
          minutes = parts[1].to_i
          return nil if hour > 23 || minutes > 59
          return format('%02d:%02d', hour, minutes)
        end

        nil
      end

      def format_time_for_display(time_24h)
        hour, minutes = time_24h.split(':').map(&:to_i)
        meridiem = hour >= 12 ? 'pm' : 'am'
        display_hour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)

        if minutes == 0
          "#{display_hour}#{meridiem}"
        else
          "#{display_hour}:#{format('%02d', minutes)}#{meridiem}"
        end
      end

      def parse_delay(delay_string)
        # Try relative delay first (e.g., "3 hours", "2 days", "1 week")
        if (match = delay_string.match(/(\d+)\s*(hour|day|week)s?/i))
          amount = match[1].to_i
          unit = match[2].downcase

          return case unit
          when 'hour'
            amount.hours.from_now
          when 'day'
            amount.days.from_now
          when 'week'
            amount.weeks.from_now
          end
        end

        # Try absolute time parsing (e.g., "4pm", "at 3:30pm", "tomorrow 9am")
        parse_absolute_time(delay_string)
      end

      def parse_absolute_time(time_string)
        user_tz = ActiveSupport::TimeZone[@user.timezone_or_default]
        now = Time.current.in_time_zone(user_tz)

        # Clean up the string
        cleaned = time_string.downcase.strip.gsub(/^at\s+/, '')

        # Check for "tomorrow" prefix
        tomorrow = cleaned.include?('tomorrow')
        cleaned = cleaned.gsub('tomorrow', '').strip if tomorrow

        # Match time patterns: "4pm", "4:30pm", "16:00", "4 pm"
        time_match = cleaned.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i)
        return nil unless time_match

        hour = time_match[1].to_i
        minutes = time_match[2]&.to_i || 0
        meridiem = time_match[3]&.downcase

        # Convert to 24-hour format
        if meridiem == 'pm' && hour < 12
          hour += 12
        elsif meridiem == 'am' && hour == 12
          hour = 0
        end

        # Build the target time directly in user's timezone
        target_date = tomorrow ? now.to_date + 1.day : now.to_date
        target_time = user_tz.local(target_date.year, target_date.month, target_date.day, hour, minutes)

        # If the time is in the past (and not tomorrow), assume they mean tomorrow
        if target_time <= now && !tomorrow
          target_time += 1.day
        end

        target_time
      rescue => e
        Rails.logger.warn("[ManageCheckIn] Failed to parse absolute time '#{time_string}': #{e.message}")
        nil
      end

      def publish_goal_updated
        return unless @agentable.goal?

        # Build next check-in info for SSE payload
        next_check_in = nil
        candidates = []

        # Check scheduled check-in
        if (scheduled = @agentable.scheduled_check_in)
          candidates << {
            type: 'scheduled',
            scheduled_for: scheduled['scheduled_for'],
            intent: scheduled['intent']
          }
        end

        # Check follow-up
        if (follow_up = @agentable.next_follow_up)
          candidates << {
            type: 'follow_up',
            scheduled_for: follow_up['scheduled_for'],
            intent: follow_up['intent']
          }
        end

        if candidates.any?
          next_check_in = candidates.min_by { |c| Time.parse(c[:scheduled_for]) }
        end

        channel = Streams::Channels.global_for_user(user: @user)
        Streams::Broker.publish(
          channel,
          event: 'goal_updated',
          data: {
            goal_id: @agentable.id,
            title: @agentable.title,
            status: @agentable.status,
            updated_at: Time.current.iso8601,
            next_check_in: next_check_in,
            check_in_schedule: @agentable.check_in_schedule
          }
        )
      end

      def friendly_follow_up_message(scheduled_time)
        user_timezone = @user.timezone_or_default
        now = Time.current.in_time_zone(user_timezone)
        scheduled_in_tz = scheduled_time.in_time_zone(user_timezone)

        today = now.to_date
        scheduled_date = scheduled_in_tz.to_date
        days_until = (scheduled_date - today).to_i

        time_phrase = if days_until == 0
          "later today"
        elsif days_until == 1
          "tomorrow"
        elsif days_until <= 3
          "in a couple days"
        elsif days_until <= 7
          "later this week"
        elsif days_until <= 14
          "next week"
        else
          "in #{scheduled_in_tz.strftime('%B')}"
        end

        "I'll follow up #{time_phrase}"
      end
    end
  end
end
