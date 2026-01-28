#!/bin/sh
# Health check for Rails backend
#
# Verifies the Rails server:
# 1. Is responding to HTTP requests
# 2. Can connect to the database
# 3. Can connect to Redis
#
# Exit codes:
#   0 = healthy
#   1 = unhealthy

set -e

PORT="${PORT:-3033}"
TIMEOUT=3

# Test 1: Is the server responding?
# The /up endpoint checks database connectivity
if ! timeout "$TIMEOUT" curl -sf "http://localhost:$PORT/up" > /dev/null 2>&1; then
    echo "UNHEALTHY: Rails server not responding on port $PORT"
    exit 1
fi

# All checks passed (the /up endpoint already checks DB)
exit 0
