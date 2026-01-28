# frozen_string_literal: true

namespace :jobs do
  desc 'Verify all scheduled jobs and repair if needed'
  task verify: :environment do
    require 'sidekiq/api'

    puts "Verifying all scheduled jobs...\n\n"

    feed_fixed = 0
    feed_healthy = 0
    checkin_fixed = 0
    checkin_healthy = 0
    errors = 0

    scheduled_set = Sidekiq::ScheduledSet.new

    # === VERIFY FEED SCHEDULES ===
    puts "=== Feed Schedules ===\n"
    UserAgent.find_each do |user_agent|
      schedule = user_agent.runtime_state&.dig('feed_schedule')

      unless schedule && schedule['enabled'] != false
        puts "  - User #{user_agent.user_id}: Scheduling disabled"
        next
      end

      jobs = schedule['jobs'] || {}
      if jobs.empty?
        puts "  - User #{user_agent.user_id}: No jobs configured"
        next
      end

      missing_jobs = jobs.select do |period, job_data|
        !scheduled_set.find { |j| j.jid == job_data['job_id'] }
      end

      if missing_jobs.any?
        puts "  ⚠ User #{user_agent.user_id}: Missing #{missing_jobs.count}/#{jobs.count} jobs - rescheduling..."

        begin
          scheduler = Feeds::InsightScheduler.new(user_agent)
          scheduler.cancel_all!
          scheduler.schedule_all!

          puts "  ✓ User #{user_agent.user_id}: Rescheduled all feed jobs"
          feed_fixed += 1
        rescue StandardError => e
          puts "  ✗ User #{user_agent.user_id}: ERROR - #{e.message}"
          errors += 1
        end
      else
        puts "  ✓ User #{user_agent.user_id}: All #{jobs.count} feed jobs healthy"
        feed_healthy += 1
      end
    end

    # === VERIFY CHECK-INS ===
    puts "\n=== Check-Ins ===\n"
    Goal.find_each do |goal|
      check_ins = goal.runtime_state&.dig('check_ins') || {}

      if check_ins.empty?
        next
      end

      # Check delay-based check-ins
      if (delay_checkin = check_ins['delay_based'])
        job_id = delay_checkin['job_id']
        scheduled_for = Time.parse(delay_checkin['scheduled_for']) rescue nil

        if job_id && scheduled_for && !scheduled_set.find_job(job_id)
          puts "  ⚠ Goal #{goal.id}: Missing delay check-in - rescheduling..."

          begin
            new_job_id = Jobs::Scheduler.schedule_check_in(
              goal,
              'delay',
              scheduled_for,
              delay_checkin['intent']
            )

            # Update stored job_id
            state = goal.runtime_state.dup
            state['check_ins']['delay_based']['job_id'] = new_job_id
            goal.update_column(:runtime_state, state)

            puts "  ✓ Goal #{goal.id}: Rescheduled check-in"
            checkin_fixed += 1
          rescue StandardError => e
            puts "  ✗ Goal #{goal.id}: ERROR - #{e.message}"
            errors += 1
          end
        elsif job_id && scheduled_set.find_job(job_id)
          puts "  ✓ Goal #{goal.id}: Check-in healthy (#{delay_checkin['intent']})"
          checkin_healthy += 1
        end
      end
    end

    # === SUMMARY ===
    puts "\n=== Summary ===\n"
    puts "  Feed Schedules:"
    puts "    Healthy: #{feed_healthy} users"
    puts "    Repaired: #{feed_fixed} users" if feed_fixed > 0
    puts "\n  Check-Ins:"
    puts "    Healthy: #{checkin_healthy} goals"
    puts "    Repaired: #{checkin_fixed} goals" if checkin_fixed > 0
    puts "\n  Errors: #{errors}" if errors > 0
  end

  desc 'Show all scheduled jobs by type'
  task show: :environment do
    require 'sidekiq/api'

    puts "=== Scheduled Jobs ===\n\n"

    # === FEED SCHEDULES ===
    puts "=== Feed Schedules ===\n"
    UserAgent.find_each do |user_agent|
      schedule = user_agent.runtime_state&.dig('feed_schedule')

      if schedule.nil?
        puts "User #{user_agent.user_id}: No schedule configured"
        next
      end

      enabled = schedule['enabled'] != false
      jobs = schedule['jobs'] || {}

      puts "User #{user_agent.user_id}:"
      puts "  Enabled: #{enabled}"
      puts "  Times: #{schedule['times']&.join(', ')}"

      if jobs.any?
        puts "  Scheduled jobs:"
        jobs.each do |period, job_data|
          puts "    #{period.capitalize}: #{job_data['scheduled_for']} (job_id: #{job_data['job_id']})"
        end
      else
        puts "  No jobs scheduled"
      end

      puts ""
    end

    # === CHECK-INS ===
    puts "\n=== Check-Ins ===\n"
    goals_with_checkins = Goal.where("runtime_state -> 'check_ins' IS NOT NULL")
    if goals_with_checkins.empty?
      puts "No goals with scheduled check-ins\n"
    else
      goals_with_checkins.each do |goal|
        check_ins = goal.runtime_state&.dig('check_ins') || {}
        next if check_ins.empty?

        puts "Goal #{goal.id} (#{goal.title}):"

        if (delay_checkin = check_ins['delay_based'])
          puts "  Delay-based:"
          puts "    Intent: #{delay_checkin['intent']}"
          puts "    Scheduled: #{delay_checkin['scheduled_for']}"
          puts "    Job ID: #{delay_checkin['job_id']}"
        end

        if (recurring_checkin = check_ins['recurring'])
          puts "  Recurring:"
          puts "    Intent: #{recurring_checkin['intent']}"
          puts "    Schedule: #{recurring_checkin['schedule']}"
          puts "    Job ID: #{recurring_checkin['job_id']}"
        end

        puts ""
      end
    end

    # === CRON JOBS ===
    puts "\n=== Cron Jobs ===\n"
    if defined?(Sidekiq::Cron::Job)
      Sidekiq::Cron::Job.all.each do |job|
        puts "#{job.name}:"
        puts "  Class: #{job.klass}"
        puts "  Schedule: #{job.cron}"
        puts "  Last run: #{job.last_enqueue_time || 'Never'}"
        puts "  Status: #{job.status}"
        puts ""
      end
    else
      puts "Sidekiq Cron not available\n"
    end

    # === SIDEKIQ STATS ===
    puts "\n=== Sidekiq Stats ===\n"
    stats = Sidekiq::Stats.new
    puts "  Scheduled jobs: #{stats.scheduled_size}"
    puts "  Queued jobs: #{stats.enqueued}"
    puts "  Processing: #{stats.processes_size}"
    puts "  Failed: #{stats.failed}"
    puts "  Retries: #{stats.retry_size}"
  end

  desc 'Cancel all user-scheduled jobs (feed schedules and check-ins)'
  task cancel_all: :environment do
    require 'sidekiq/api'

    puts "Canceling all user-scheduled jobs...\n\n"

    feed_count = 0
    checkin_count = 0

    # === CANCEL FEED SCHEDULES ===
    puts "=== Feed Schedules ===\n"
    UserAgent.find_each do |user_agent|
      begin
        scheduler = Feeds::InsightScheduler.new(user_agent)
        scheduler.cancel_all!

        puts "  ✓ User #{user_agent.user_id}: Canceled all feed schedules"
        feed_count += 1
      rescue StandardError => e
        puts "  ✗ User #{user_agent.user_id}: ERROR - #{e.message}"
      end
    end

    # === CANCEL CHECK-INS ===
    puts "\n=== Check-Ins ===\n"
    Goal.find_each do |goal|
      check_ins = goal.runtime_state&.dig('check_ins') || {}
      next if check_ins.empty?

      begin
        check_ins.each do |type, data|
          if data['job_id']
            Jobs::Scheduler.cancel(data['job_id'])
          end
        end

        # Clear check-ins from runtime_state
        state = goal.runtime_state.dup
        state.delete('check_ins')
        goal.update_column(:runtime_state, state)

        puts "  ✓ Goal #{goal.id}: Canceled all check-ins"
        checkin_count += 1
      rescue StandardError => e
        puts "  ✗ Goal #{goal.id}: ERROR - #{e.message}"
      end
    end

    puts "\n=== Summary ===\n"
    puts "  Canceled feed schedules: #{feed_count} users"
    puts "  Canceled check-ins: #{checkin_count} goals"
  end
end
