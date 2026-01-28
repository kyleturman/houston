# frozen_string_literal: true

namespace :feed do
  desc 'Setup feed insight schedules for all existing users'
  task setup_schedules: :environment do
    puts "Setting up feed insight schedules for existing users..."

    count = 0
    errors = 0

    UserAgent.find_each do |user_agent|
      begin
        scheduler = Feeds::InsightScheduler.new(user_agent)
        scheduler.schedule_all!

        puts "  ✓ User #{user_agent.user_id}: Scheduled morning, noon, evening insights"
        count += 1
      rescue StandardError => e
        puts "  ✗ User #{user_agent.user_id}: ERROR - #{e.message}"
        errors += 1
      end
    end

    puts "\nDone!"
    puts "  Successfully scheduled: #{count} users"
    puts "  Errors: #{errors} users" if errors.positive?
  end

  desc 'Show feed schedules for all users'
  task show_schedules: :environment do
    puts "Feed insight schedules:\n\n"

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
  end

  desc 'Cancel all feed schedules'
  task cancel_schedules: :environment do
    puts "Canceling all feed insight schedules..."

    count = 0

    UserAgent.find_each do |user_agent|
      begin
        scheduler = Feeds::InsightScheduler.new(user_agent)
        scheduler.cancel_all!

        puts "  ✓ User #{user_agent.user_id}: Canceled all schedules"
        count += 1
      rescue StandardError => e
        puts "  ✗ User #{user_agent.user_id}: ERROR - #{e.message}"
      end
    end

    puts "\nDone! Canceled schedules for #{count} users"
  end

  desc 'Verify and repair feed schedules (run after server restart)'
  task verify_schedules: :environment do
    require 'sidekiq/api'

    puts "Verifying feed schedules...\n"

    fixed = 0
    healthy = 0
    errors = 0

    UserAgent.find_each do |user_agent|
      begin
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

        # Check if jobs exist in Sidekiq
        scheduled_set = Sidekiq::ScheduledSet.new
        missing_jobs = jobs.select do |period, job_data|
          !scheduled_set.find { |j| j.jid == job_data['job_id'] }
        end

        if missing_jobs.any?
          puts "  ⚠ User #{user_agent.user_id}: Missing #{missing_jobs.count}/#{jobs.count} jobs - rescheduling..."

          scheduler = Feeds::InsightScheduler.new(user_agent)
          scheduler.cancel_all!
          scheduler.schedule_all!

          puts "  ✓ User #{user_agent.user_id}: Rescheduled all jobs"
          fixed += 1
        else
          puts "  ✓ User #{user_agent.user_id}: All #{jobs.count} jobs healthy"
          healthy += 1
        end
      rescue StandardError => e
        puts "  ✗ User #{user_agent.user_id}: ERROR - #{e.message}"
        errors += 1
      end
    end

    puts "\nSummary:"
    puts "  Healthy: #{healthy} users"
    puts "  Fixed: #{fixed} users" if fixed > 0
    puts "  Errors: #{errors} users" if errors > 0
  end
end
