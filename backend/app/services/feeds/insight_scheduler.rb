# frozen_string_literal: true

module Feeds
  # Per-user scheduling of feed insight generation
  # Each user has 3 daily jobs (morning, afternoon, evening) that self-reschedule
  class InsightScheduler
    RANDOMIZATION_WINDOW = 15.minutes  # Generate up to 15 min before scheduled time

    # Default per-period configuration
    DEFAULT_PERIODS = {
      'morning' => { 'enabled' => true, 'time' => '06:00' },
      'afternoon' => { 'enabled' => true, 'time' => '12:00' },
      'evening' => { 'enabled' => true, 'time' => '17:00' }
    }.freeze

    # Valid time ranges for each period (hour only, HH:00 format)
    TIME_RANGES = {
      'morning' => (4..11),    # 4am-11am
      'afternoon' => (12..16), # 12pm-4pm
      'evening' => (17..22)    # 5pm-10pm
    }.freeze

    PERIODS = %w[morning afternoon evening].freeze

    def initialize(user_agent)
      @user_agent = user_agent
      @user = user_agent.user
    end

    # Setup all daily jobs for a user (only enabled periods)
    def schedule_all!
      PERIODS.each do |period|
        schedule_next(period) if period_enabled?(period)
      end
    end

    # Schedule next occurrence for a specific period
    def schedule_next(period)
      return unless period_enabled?(period)

      time_of_day = period_time(period)
      next_run_time = calculate_next_run(time_of_day)

      # Schedule via Jobs::Scheduler
      job_id = Jobs::Scheduler.schedule_feed_insights(@user_agent, period, next_run_time)

      # Store job ID for cancellation/tracking
      update_schedule(period, job_id, next_run_time, time_of_day)

      job_id
    end

    # Check if a specific period is enabled
    def period_enabled?(period)
      periods_config.dig(period, 'enabled') != false
    end

    # Get time for a specific period
    def period_time(period)
      periods_config.dig(period, 'time') || DEFAULT_PERIODS.dig(period, 'time')
    end

    # Get all periods config
    def periods_config
      schedule_config['periods'] || DEFAULT_PERIODS
    end

    # Update a single period's settings
    def update_period!(period, time: nil, enabled: nil)
      raise ArgumentError, "Invalid period: #{period}" unless PERIODS.include?(period)

      if time.present?
        hour = time.split(':').first.to_i
        unless TIME_RANGES[period].include?(hour)
          raise ArgumentError, "Time #{time} is outside valid range for #{period} (#{TIME_RANGES[period].first}:00-#{TIME_RANGES[period].last}:00)"
        end
      end

      @user_agent.update_runtime_state! do |state|
        state['feed_schedule'] ||= default_config
        state['feed_schedule']['periods'] ||= DEFAULT_PERIODS.deep_dup
        state['feed_schedule']['periods'][period] ||= {}
        state['feed_schedule']['periods'][period]['time'] = time if time.present?
        state['feed_schedule']['periods'][period]['enabled'] = enabled unless enabled.nil?
      end

      # Reschedule the job for this period
      reschedule_period!(period)
    end

    # Reschedule a single period's job
    def reschedule_period!(period)
      # Cancel existing job for this period
      if (job_data = schedule_config.dig('jobs', period)) && job_data['job_id']
        cancel_job(job_data['job_id'])
      end

      # Schedule new job if enabled
      if period_enabled?(period)
        schedule_next(period)
      else
        # Clear job data for disabled period
        clear_period_job!(period)
      end
    end

    # Cancel all scheduled jobs for this user
    def cancel_all!
      schedule_config['jobs']&.each do |period, job_data|
        if job_data['job_id']
          cancel_job(job_data['job_id'])
          Rails.logger.info("[FeedScheduler] Cancelled #{period} job for user #{@user.id}")
        end
      end

      clear_schedule!
    end

    # Check if scheduling is enabled
    def enabled?
      schedule_config['enabled'] != false
    end

    # Disable scheduling (cancels all jobs)
    def disable!
      cancel_all!
      @user_agent.update_runtime_state! do |state|
        state['feed_schedule'] ||= default_config
        state['feed_schedule']['enabled'] = false
      end
    end

    # Enable scheduling (creates new jobs)
    def enable!
      @user_agent.update_runtime_state! do |state|
        state['feed_schedule'] ||= default_config
        state['feed_schedule']['enabled'] = true
      end

      schedule_all!
    end

    private

    def schedule_config
      (@user_agent.feed_schedule || default_config).dup
    end

    def default_config
      {
        'enabled' => true,
        'periods' => DEFAULT_PERIODS.deep_dup,
        'jobs' => {}
      }
    end

    def clear_period_job!(period)
      @user_agent.update_runtime_state! do |state|
        state['feed_schedule'] ||= default_config
        state['feed_schedule']['jobs'] ||= {}
        state['feed_schedule']['jobs'].delete(period)
      end
    end

    # Calculate next run time in user's timezone with randomization
    def calculate_next_run(time_of_day)
      hour, minute = time_of_day.split(':').map(&:to_i)
      timezone = @user.timezone_or_default

      # Next occurrence in user's timezone
      now = Time.current.in_time_zone(timezone)
      target = now.change(hour: hour, min: minute, sec: 0)

      # If time passed today, schedule for tomorrow
      target = target + 1.day if target < now

      # Generate 0-15 min before scheduled time (ensures feed is ready when user expects it)
      early_offset = rand(0..RANDOMIZATION_WINDOW.to_i)
      result = target - early_offset.seconds

      # If early offset pushed us into the past, schedule for tomorrow instead
      # This prevents infinite reschedule loops when jobs run near their scheduled time
      result = result + 1.day if result < now

      result
    end

    def update_schedule(period, job_id, scheduled_for, time)
      @user_agent.update_runtime_state! do |state|
        state['feed_schedule'] ||= default_config
        state['feed_schedule']['jobs'] ||= {}
        state['feed_schedule']['jobs'][period] = {
          'job_id' => job_id,
          'scheduled_for' => scheduled_for.iso8601,
          'time' => time
        }
      end
    end

    def clear_schedule!
      @user_agent.update_runtime_state! do |state|
        state['feed_schedule'] ||= default_config
        state['feed_schedule']['jobs'] = {}
      end
    end

    def cancel_job(job_id)
      Jobs::Scheduler.cancel(job_id)
    end
  end
end
