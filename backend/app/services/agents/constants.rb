# frozen_string_literal: true

module Agents
  # Centralized constants for agent behavior, retry logic, and limits
  module Constants
    # ========================================================================
    # CORELOOP LIMITS
    # ========================================================================

    # Maximum number of ReAct iterations per agent execution
    MAX_ITERATIONS = 20

    # Maximum times the same tool can be called consecutively
    MAX_SAME_TOOL_CONSECUTIVE = 5

    # Maximum wall-clock time for agent execution
    MAX_EXECUTION_TIME = 10.minutes

    # Maximum number of messages kept in task history
    MAX_TASK_HISTORY_LENGTH = 20

    # ========================================================================
    # IMMEDIATE RETRIES (CoreLoop level - during LLM call)
    # ========================================================================

    # Number of immediate retries for transient rate limits
    RATE_LIMIT_IMMEDIATE_RETRIES = 2

    # Delay between immediate retries (seconds)
    RATE_LIMIT_IMMEDIATE_DELAY = 1.5

    # ========================================================================
    # DELAYED RETRIES (Orchestrator level - between agent runs)
    # ========================================================================

    # Base delay for rate limit errors (seconds)
    RATE_LIMIT_BASE_DELAY = 10

    # Base delay for network/timeout errors (seconds)
    NETWORK_ERROR_BASE_DELAY = 10

    # Maximum retry delay cap (seconds)
    MAX_RETRY_DELAY = 300  # 5 minutes

    # Random jitter added to retry delay (0 to N seconds)
    RETRY_JITTER_RANGE = 2

    # ========================================================================
    # MAXIMUM RETRY ATTEMPTS (by error type)
    # ========================================================================

    # Maximum retries for rate limit errors
    MAX_RETRIES_RATE_LIMIT = 5

    # Maximum retries for network/timeout errors
    MAX_RETRIES_NETWORK = 3

    # Maximum retries for other retryable errors
    MAX_RETRIES_DEFAULT = 2

    # ========================================================================
    # HEALTH MONITOR
    # ========================================================================

    # How often HealthMonitor checks for stuck/paused agents
    HEALTH_CHECK_INTERVAL = 5.minutes

    # Stale agent thresholds - when to mark agents as stale/stuck
    STALE_TASK_THRESHOLD_PRODUCTION = 2.hours
    STALE_TASK_THRESHOLD_DEV = 1.hour
    STALE_GOAL_THRESHOLD_PRODUCTION = 6.hours
    STALE_GOAL_THRESHOLD_DEV = 3.hours
    STUCK_ORCHESTRATOR_THRESHOLD = 30.minutes  # Running flag set for > 30 min (reduced from 1hr)

    # History and tool usage limits for health checks
    HEALTH_EXCESSIVE_HISTORY_LIMIT = 100  # Stop tasks with > 100 messages
    HEALTH_HIGH_HISTORY_WARNING = 25      # Warn at 25 messages
    HEALTH_TOOL_REPETITION_LIMIT = 5      # Same tool used > 5 times
    HEALTH_MIN_TOOL_CALLS = 5             # Only check repetition if > 5 tool calls

    # Retry and expiry timeouts
    HEALTH_RETRY_FAILED_DELAY = 30.minutes
    PAUSED_TASK_EXPIRY_THRESHOLD = 24.hours
    COMPLETED_TASK_CLEANUP_THRESHOLD = 15.days

    # User stop command detection window
    USER_STOP_COMMAND_WINDOW = 5.minutes

    # ========================================================================
    # AGENT HISTORY & SESSION MANAGEMENT
    # ========================================================================

    # Session timeout - archive llm_history after this period of inactivity
    SESSION_TIMEOUT = ENV.fetch('AGENT_SESSION_TIMEOUT', '30').to_i.minutes

    # How many agent_history summaries to include in agent context
    AGENT_HISTORY_SUMMARY_COUNT = ENV.fetch('AGENT_HISTORY_SUMMARY_COUNT', '5').to_i

    # Archive reasons that indicate autonomous (system-initiated) sessions
    # These sessions are archived differently:
    # - Require tool calls to be worth archiving (no empty summaries)
    # - Use "Checked on..." style summaries instead of "User asked..."
    #
    # Note: Check-ins use context type 'agent_check_in' but archive via
    # 'session_timeout' since they create ThreadMessages during execution.
    AUTONOMOUS_ARCHIVE_REASONS = %w[feed_generation_complete].freeze

    # ========================================================================
    # CHECK-IN SYSTEM
    # ========================================================================
    # Check-ins are scheduled agent executions that review goals autonomously.
    #
    # Two types of check-ins:
    #   1. Recurring schedule (check_in_schedule): Daily, weekdays, weekly
    #   2. Follow-ups (next_follow_up): One-time contextual follow-ups
    #
    # Sources that create check-ins:
    #   - Agent (via set_schedule or schedule_follow_up actions)
    #   - Note-triggered (when user adds a note) - creates follow-up
    #   - System heartbeat (ensures goals never go silent) - creates follow-up

    # NOTE-TRIGGERED CHECK-INS
    # When user adds a note, agent reviews quickly to decide if action needed
    NOTE_TRIGGERED_DELAY_MINUTES = 15
    # Skip note-triggered if scheduled check-in is within this window
    NOTE_TRIGGERED_SKIP_IF_SCHEDULED_WITHIN_HOURS = 2
    # Debounce rapid notes (don't reschedule if we just did)
    NOTE_TRIGGERED_DEBOUNCE_MINUTES = 15

    # HEARTBEAT CHECK-INS (fallback if no schedule or follow-up exists)
    # Base intervals by activity level (hours) - used for follow-ups only
    HEARTBEAT_HIGH_ACTIVITY_HOURS = 12
    HEARTBEAT_MODERATE_ACTIVITY_HOURS = 48
    HEARTBEAT_LOW_ACTIVITY_HOURS = 120  # 5 days

    # Follow-up delay limits (for agent-scheduled follow-ups)
    MIN_CHECK_IN_DELAY_HOURS = 1
    MAX_CHECK_IN_DELAY_DAYS = 30

    # Check-in execution limits (cost control)
    CHECK_IN_MAX_LLM_CALLS = 3
    CHECK_IN_MAX_EXECUTION_TIME = 45.seconds

    # ========================================================================
    # ACTIVITY LEVEL CALCULATION
    # ========================================================================
    # Used to determine appropriate check-in intervals based on goal engagement.
    # Counts notes + messages in the activity window.

    # How far back to look for activity
    ACTIVITY_WINDOW_DAYS = 7

    # Thresholds for activity levels (based on weighted score)
    # Score = (notes * 1.5) + messages
    ACTIVITY_HIGH_THRESHOLD = 5      # 5+ = high activity
    ACTIVITY_MODERATE_THRESHOLD = 2  # 2-4 = moderate, 0-1 = low

    # ========================================================================
    # LEARNINGS
    # ========================================================================

    # Maximum learnings per goal (prevent unbounded growth)
    MAX_LEARNINGS_PER_GOAL = 50
  end
end
