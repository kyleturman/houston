# Background Jobs

This directory contains Sidekiq jobs that handle asynchronous processing.

## Job Categories

### Feed Generation

| Job | Schedule | Description |
|-----|----------|-------------|
| `GenerateFeedInsightsJob` | 3x daily per user | Triggers UserAgent to generate feed insights. Self-reschedules for next occurrence. |
| `VerifyScheduledJobsJob` | Hourly (cron) | Safety net that repairs missing Sidekiq jobs and triggers missed feed generations. |
| `CleanupOldFeedInsightsJob` | Daily (cron) | Removes feed insights older than 7 days. |

**Related services:**
- `Feeds::GenerationGuard` - Centralized validation (insights exist, in progress, max attempts)
- `Feeds::InsightScheduler` - Manages per-user scheduling

### Goal Check-ins

| Job | Trigger | Description |
|-----|---------|-------------|
| `AgentCheckInJob` | Scheduled | Executes agent check-ins (scheduled or follow-up) by triggering the orchestrator. |
| `NoteTriggeredCheckInJob` | On note creation | Ensures agent reviews notes within a reasonable time by scheduling/adjusting follow-ups. |

### Note Processing

| Job | Trigger | Description |
|-----|---------|-------------|
| `ProcessUrlNoteJob` | On URL note creation | Fetches web content, generates AI summary, extracts images. |

### Maintenance

| Job | Schedule | Description |
|-----|----------|-------------|
| `CleanupStaleDevicesJob` | Daily at 4 AM | Removes devices unused for 30+ days. |

## Cron Configuration

Cron jobs are configured in `config/initializers/sidekiq_cron.rb`:

```ruby
Sidekiq::Cron::Job.create(name: 'VerifyScheduledJobs - hourly', cron: '0 * * * *', ...)
Sidekiq::Cron::Job.create(name: 'CleanupOldFeedInsights - daily', cron: '0 3 * * *', ...)
Sidekiq::Cron::Job.create(name: 'CleanupStaleDevices - daily', cron: '0 4 * * *', ...)
```

## Common Patterns

### Self-Rescheduling Jobs
`GenerateFeedInsightsJob` reschedules itself after each execution. If it fails to reschedule, `VerifyScheduledJobsJob` acts as a safety net.

### Deduplication
Feed generation uses `Feeds::GenerationGuard` to prevent duplicate runs:
- Check if insights already exist for the period
- Check if generation is currently in progress
- Limit attempts per period per day (max 3)

### Job Tracking
Jobs store their Sidekiq job IDs in `runtime_state` for:
- Cancellation when schedules change
- Verification by `VerifyScheduledJobsJob`

## Debugging

Check Sidekiq scheduled jobs:
```ruby
# In rails console
require 'sidekiq/api'
Sidekiq::ScheduledSet.new.each { |job| puts "#{job.klass}: #{job.at}" }
```

Check cron jobs:
```ruby
Sidekiq::Cron::Job.all.each { |job| puts "#{job.name}: #{job.last_enqueue_time}" }
```
