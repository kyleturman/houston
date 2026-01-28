# frozen_string_literal: true

# Migrate legacy runtime_state formats so backward-compat code can be removed.
#
# 1. feed_attempts: convert {date: "2026-01-27", count: N} → {recorded_at: "<iso8601>", count: N}
#    The old date-string format compared against today's date. The new format uses a 24h rolling
#    window with a timestamp. We set recorded_at to start-of-day for the stored date so existing
#    counts expire naturally within 24h of migration.
#
# 2. feed_schedule.times: convert ["06:00","12:00","17:00"] → periods hash format.
#    No users currently have this format, but included defensively.
class MigrateLegacyFeedFormats < ActiveRecord::Migration[8.0]
  def up
    # 1. Migrate feed_attempts date format → recorded_at format
    UserAgent.where("runtime_state ? 'feed_attempts'").find_each do |ua|
      attempts = ua.runtime_state['feed_attempts']
      next unless attempts.is_a?(Hash)

      changed = false
      attempts.each do |period, data|
        next unless data.is_a?(Hash) && data.key?('date') && !data.key?('recorded_at')

        # Convert date string to ISO8601 timestamp (start of that day)
        date_str = data['date']
        begin
          data['recorded_at'] = Time.parse("#{date_str} 00:00:00 UTC").iso8601
        rescue ArgumentError
          data['recorded_at'] = Time.current.iso8601
        end
        data.delete('date')
        changed = true
      end

      if changed
        ua.update_column(:runtime_state, ua.runtime_state)
      end
    end

    # 2. Migrate feed_schedule.times array → periods hash
    UserAgent.where("runtime_state->'feed_schedule' ? 'times'").find_each do |ua|
      schedule = ua.runtime_state['feed_schedule']
      next unless schedule.is_a?(Hash) && schedule['times'].is_a?(Array)

      old_times = schedule['times']
      schedule['periods'] = {
        'morning' => { 'enabled' => true, 'time' => old_times[0] || '06:00' },
        'afternoon' => { 'enabled' => true, 'time' => old_times[1] || '12:00' },
        'evening' => { 'enabled' => true, 'time' => old_times[2] || '17:00' }
      }
      schedule.delete('times')

      ua.update_column(:runtime_state, ua.runtime_state)
    end
  end

  def down
    # Not reversible — old formats are strictly worse and the new code doesn't write them
  end
end
