-- Houston database initialization
-- This file is executed automatically by the Postgres container on first startup.
-- The database and role are already created via POSTGRES_* env vars in docker-compose.
-- Add any required extensions or seed SQL here.

-- Useful extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
