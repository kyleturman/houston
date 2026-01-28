#!/bin/bash
# Health Watchdog - Monitors backend server and auto-restarts if hung
# Run this in the background: ./scripts/health_watchdog.sh &

set -euo pipefail

# Configuration
CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-30}  # seconds between checks
TIMEOUT=${HEALTH_CHECK_TIMEOUT:-5}           # timeout for health check request
MAX_FAILURES=${HEALTH_MAX_FAILURES:-3}       # consecutive failures before restart
HEALTH_URL=${HEALTH_URL:-"http://localhost:3000/up"}
LOG_FILE=${HEALTH_LOG_FILE:-"log/health_watchdog.log"}

# State
failure_count=0
last_restart=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_health() {
    if timeout "$TIMEOUT" curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
        return 0  # healthy
    else
        return 1  # unhealthy
    fi
}

restart_backend() {
    local now=$(date +%s)
    local since_last=$((now - last_restart))

    # Prevent restart loops - require at least 2 minutes between restarts
    if [ $since_last -lt 120 ]; then
        log "WARNING: Too soon since last restart ($since_last seconds). Skipping to prevent restart loop."
        return 1
    fi

    log "CRITICAL: Restarting backend container due to health check failures..."

    # Try graceful restart first
    if docker-compose restart backend 2>&1 | tee -a "$LOG_FILE"; then
        log "Backend restarted successfully"
        last_restart=$now
        failure_count=0

        # Wait for startup
        log "Waiting 30s for backend to start..."
        sleep 30

        return 0
    else
        log "ERROR: Failed to restart backend"
        return 1
    fi
}

main() {
    log "Health watchdog started (check every ${CHECK_INTERVAL}s, timeout ${TIMEOUT}s, max failures ${MAX_FAILURES})"

    while true; do
        if check_health; then
            if [ $failure_count -gt 0 ]; then
                log "Backend recovered (was unhealthy for $failure_count check(s))"
            fi
            failure_count=0
        else
            ((failure_count++))
            log "Health check failed ($failure_count/$MAX_FAILURES)"

            if [ $failure_count -ge $MAX_FAILURES ]; then
                log "ALERT: Backend appears hung after $MAX_FAILURES consecutive failures"

                # Gather diagnostic info before restart
                log "=== Diagnostic Info ==="
                docker-compose ps backend 2>&1 | tee -a "$LOG_FILE"
                docker-compose logs backend --tail=50 2>&1 | tee -a "$LOG_FILE"
                log "======================"

                restart_backend
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Handle signals
trap 'log "Watchdog stopped"; exit 0' SIGTERM SIGINT

# Run
main
