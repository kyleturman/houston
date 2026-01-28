#!/usr/bin/env bash
set -euo pipefail

# Houston - Initialize secrets only
# Generates required secrets without any user interaction
# Safe to run multiple times (skips existing values)
# Does NOT require Docker - uses openssl for secret generation

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
cd "$ROOT_DIR"

echo "🔐 Initializing Houston secrets..."

# Portable in-place sed
UNAME_S=$(uname -s)
if [ "$UNAME_S" = "Darwin" ]; then
  SED_INPLACE=(sed -i '' -e)
else
  SED_INPLACE=(sed -i -e)
fi

# Check for openssl (available on macOS and most Linux)
if ! command -v openssl >/dev/null 2>&1; then
  echo "❌ openssl not found. Please install openssl."
  exit 1
fi

# Create .env if it doesn't exist
if [ ! -f .env ]; then
  echo "📋 Creating .env from .env.example..."
  cp .env.example .env
fi

# Generate secret helper (uses openssl, no docker needed)
generate_secret() {
  local key="$1"
  local bytes="$2"

  if grep -qE "^${key}=\s*$" .env; then
    echo "   Generating ${key}..."
    SECRET=$(openssl rand -hex "$bytes")
    "${SED_INPLACE[@]}" "s|^${key}=.*|${key}=${SECRET}|" .env
    echo "   ✅ ${key}"
  else
    echo "   ⏭️  ${key} already set"
  fi
}

# Generate all required secrets
generate_secret "SECRET_KEY_BASE" 64
generate_secret "USER_ENCRYPTION_KEY" 32
generate_secret "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" 64
generate_secret "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" 64
generate_secret "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" 32
generate_secret "PAIRING_JWT_SECRET" 32
generate_secret "POSTGRES_PASSWORD" 32

# Generate SERVER_UUID if missing (use uuidgen if available, otherwise openssl)
if grep -qE "^SERVER_UUID=\s*$" .env || ! grep -qE "^SERVER_UUID=" .env; then
  echo "   Generating SERVER_UUID..."
  if command -v uuidgen >/dev/null 2>&1; then
    UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  else
    # Generate UUID v4 format from random bytes
    UUID=$(openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/')
  fi
  if grep -qE "^SERVER_UUID=" .env; then
    "${SED_INPLACE[@]}" "s|^SERVER_UUID=.*|SERVER_UUID=${UUID}|" .env
  else
    echo "SERVER_UUID=${UUID}" >> .env
  fi
  echo "   ✅ SERVER_UUID"
else
  echo "   ⏭️  SERVER_UUID already set"
fi

echo ""
echo "✅ Secrets initialized!"
echo ""
echo "Next steps:"
echo "  make start    Start all services"
echo "  make dev      Start with logs (foreground)"
echo ""
