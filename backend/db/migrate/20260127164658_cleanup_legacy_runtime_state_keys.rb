# frozen_string_literal: true

# Remove deprecated runtime_state keys that are no longer written or read.
#
# Keys removed:
#   orchestrator_completed_at - was set on release_execution_lock!, never read by app code
#   last_feed_at              - replaced by feed_schedule/feed_attempts
#   agent_ideas               - unused legacy key
#   feed_insights             - replaced by feed generation via tasks
#   feed_last_runs            - replaced by feed_schedule
#   check_ins                 - legacy slot-based check-in format (no records found with this key,
#                               but clean up defensively in case other instances have old data)
class CleanupLegacyRuntimeStateKeys < ActiveRecord::Migration[8.0]
  DEPRECATED_KEYS = %w[
    orchestrator_completed_at
    last_feed_at
    agent_ideas
    feed_insights
    feed_last_runs
    check_ins
  ].freeze

  def up
    # Use pure SQL for efficiency — no need to instantiate AR models
    %w[goals user_agents agent_tasks].each do |table|
      DEPRECATED_KEYS.each do |key|
        execute <<~SQL
          UPDATE #{table}
          SET runtime_state = runtime_state - '#{key}'
          WHERE runtime_state ? '#{key}'
        SQL
      end
    end
  end

  def down
    # Data removal is not reversible, but the keys are unused so no impact
  end
end
