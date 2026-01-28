#!/bin/sh
# Health check for Redis
#
# Verifies Redis can:
# 1. Accept connections (PING)
# 2. Write data (SET)
# 3. Read data (GET)
#
# Exit codes:
#   0 = healthy
#   1 = unhealthy

set -e

# Test 1: Can we connect and ping?
if ! redis-cli ping > /dev/null 2>&1; then
    echo "UNHEALTHY: Redis not responding to PING"
    exit 1
fi

# Test 2: Can we write? (This catches MISCONF errors)
TEST_KEY="health:check:$(date +%s)"
if ! redis-cli set "$TEST_KEY" "ok" EX 10 > /dev/null 2>&1; then
    echo "UNHEALTHY: Redis cannot write (possible MISCONF or disk issue)"
    exit 1
fi

# Test 3: Can we read back?
if [ "$(redis-cli get "$TEST_KEY")" != "ok" ]; then
    echo "UNHEALTHY: Redis read verification failed"
    exit 1
fi

# All checks passed
exit 0
