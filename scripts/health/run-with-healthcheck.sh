#!/bin/sh
# =============================================================================
# run-with-healthcheck.sh - Wrapper that monitors health and auto-recovers
# =============================================================================
#
# PURPOSE:
#   Runs a main process while monitoring its health. If the health check fails
#   repeatedly, this script exits, triggering Docker to restart the container.
#
# USAGE:
#   run-with-healthcheck.sh <health-check-script> <main-command...>
#
# EXAMPLE:
#   run-with-healthcheck.sh /scripts/health/check-sidekiq.sh bundle exec sidekiq
#
# CONFIGURATION (via environment variables):
#   HEALTH_CHECK_INTERVAL  - Seconds between health checks (default: 30)
#   HEALTH_CHECK_RETRIES   - Consecutive failures before exit (default: 3)
#   HEALTH_CHECK_TIMEOUT   - Timeout for each health check (default: 10)
#   HEALTH_CHECK_START_DELAY - Seconds to wait before first check (default: 30)
#
# HOW IT WORKS:
#   1. Starts the main process in the background
#   2. Waits for start delay (let process initialize)
#   3. Runs health check every INTERVAL seconds
#   4. Tracks consecutive failures
#   5. If failures >= RETRIES, logs error and exits
#   6. Docker's restart policy restarts the container
#   7. Startup verification repairs any missing scheduled jobs
#
# =============================================================================

set -e

# Configuration with sensible defaults
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-3}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"
HEALTH_CHECK_START_DELAY="${HEALTH_CHECK_START_DELAY:-30}"

# Parse arguments
HEALTH_CHECK_SCRIPT="$1"
shift
MAIN_COMMAND="$*"

if [ -z "$HEALTH_CHECK_SCRIPT" ] || [ -z "$MAIN_COMMAND" ]; then
    echo "Usage: run-with-healthcheck.sh <health-check-script> <main-command...>"
    exit 1
fi

if [ ! -x "$HEALTH_CHECK_SCRIPT" ]; then
    echo "Error: Health check script not found or not executable: $HEALTH_CHECK_SCRIPT"
    exit 1
fi

echo "=========================================="
echo "Health-Monitored Process Wrapper"
echo "=========================================="
echo "Main command: $MAIN_COMMAND"
echo "Health check: $HEALTH_CHECK_SCRIPT"
echo "Interval: ${HEALTH_CHECK_INTERVAL}s"
echo "Retries: $HEALTH_CHECK_RETRIES"
echo "Start delay: ${HEALTH_CHECK_START_DELAY}s"
echo "=========================================="

# Track consecutive failures
FAILURE_COUNT=0

# Cleanup function - kill main process on exit
cleanup() {
    echo "[Health Monitor] Shutting down..."
    if [ -n "$MAIN_PID" ]; then
        kill "$MAIN_PID" 2>/dev/null || true
        wait "$MAIN_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Start the main process in background
echo "[Health Monitor] Starting main process..."
eval "$MAIN_COMMAND" &
MAIN_PID=$!

# Check if process started
sleep 2
if ! kill -0 "$MAIN_PID" 2>/dev/null; then
    echo "[Health Monitor] ERROR: Main process failed to start"
    exit 1
fi

echo "[Health Monitor] Main process started (PID: $MAIN_PID)"
echo "[Health Monitor] Waiting ${HEALTH_CHECK_START_DELAY}s before first health check..."
sleep "$HEALTH_CHECK_START_DELAY"

# Main health monitoring loop
while true; do
    # Check if main process is still running
    if ! kill -0 "$MAIN_PID" 2>/dev/null; then
        echo "[Health Monitor] Main process exited unexpectedly"
        wait "$MAIN_PID"
        EXIT_CODE=$?
        echo "[Health Monitor] Exit code: $EXIT_CODE"
        exit "$EXIT_CODE"
    fi

    # Run health check with timeout
    if timeout "$HEALTH_CHECK_TIMEOUT" "$HEALTH_CHECK_SCRIPT" > /dev/null 2>&1; then
        # Healthy - reset failure count
        if [ "$FAILURE_COUNT" -gt 0 ]; then
            echo "[Health Monitor] Recovered after $FAILURE_COUNT failures"
        fi
        FAILURE_COUNT=0
    else
        # Unhealthy - increment failure count
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo "[Health Monitor] Health check failed ($FAILURE_COUNT/$HEALTH_CHECK_RETRIES)"

        # Run health check again to get error message for logging
        "$HEALTH_CHECK_SCRIPT" 2>&1 || true

        if [ "$FAILURE_COUNT" -ge "$HEALTH_CHECK_RETRIES" ]; then
            echo "=========================================="
            echo "[Health Monitor] CRITICAL: $HEALTH_CHECK_RETRIES consecutive failures"
            echo "[Health Monitor] Exiting to trigger container restart"
            echo "=========================================="
            exit 1
        fi
    fi

    sleep "$HEALTH_CHECK_INTERVAL"
done
