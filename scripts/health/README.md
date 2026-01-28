# Health Monitoring System

This directory contains health check scripts for Houston's Docker containers.

## How It Works

1. **Health Check Scripts** (`check-*.sh`) - Run by Docker to determine container health
2. **Wrapper Scripts** (`run-*.sh`) - Start the main process and monitor health, restarting if unhealthy

## Files

| Script | Purpose |
|--------|---------|
| `check-redis.sh` | Verifies Redis can accept read/write operations |
| `check-sidekiq.sh` | Verifies Sidekiq can communicate with Redis |
| `check-backend.sh` | Verifies Rails server is responding |
| `run-with-healthcheck.sh` | Generic wrapper that monitors health and exits on failure |

## Auto-Recovery Flow

```
Container starts
    ↓
run-with-healthcheck.sh starts main process
    ↓
Health check runs every 30s
    ↓
If unhealthy for 3 consecutive checks:
    → Wrapper script exits
    → Docker restarts container (restart: unless-stopped)
    → Startup verification repairs any missing scheduled jobs
```

## Adding a New Health Check

1. Create `check-{service}.sh` in this directory
2. Script should exit 0 for healthy, 1 for unhealthy
3. Keep checks fast (<5 seconds) and idempotent
4. Log failures for debugging

## Testing Health Checks

```bash
# Test Redis health check
docker-compose exec redis /app/scripts/health/check-redis.sh

# Test Sidekiq health check
docker-compose exec sidekiq /app/scripts/health/check-sidekiq.sh

# Simulate unhealthy state and watch recovery
docker-compose exec redis redis-cli DEBUG SLEEP 60
```
