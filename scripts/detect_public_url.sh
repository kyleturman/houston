#!/usr/bin/env bash
set -euo pipefail

# Detect a reachable IP-based URL for the host machine and write SERVER_PUBLIC_URL in .env if empty.
# Prefers Wi-Fi (en0) on macOS, falls back to the first private IPv4.
# Uses PORT from .env (or default 3000) and protocol from FORCE_SSL.

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  echo ".env not found; nothing to do." >&2
  exit 0
fi

get_env() {
  local key="$1"
  local val
  val=$(grep -E "^${key}=" .env | sed -E "s/^${key}=//") || true
  echo "$val"
}

set_env_if_empty() {
  local key="$1"; shift
  local value="$1"; shift
  if grep -qE "^${key}=" .env; then
    local existing
    existing=$(get_env "$key")
    if [ -n "$existing" ]; then
      return 0
    fi
    # fallthrough to set value when existing empty
  fi
  if grep -qE "^${key}=" .env; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      sed -i '' -e "s|^${key}=.*|${key}=${value}|" .env
    else
      sed -i -e "s|^${key}=.*|${key}=${value}|" .env
    fi
  else
    echo "${key}=${value}" >> .env
  fi
}

# Determine IP (macOS preferred path)
IP=""
if command -v ipconfig >/dev/null 2>&1; then
  IP=$(ipconfig getifaddr en0 2>/dev/null || true)
  if [ -z "$IP" ]; then
    IP=$(ipconfig getifaddr en1 2>/dev/null || true)
  fi
fi

# Generic fallback: first private IPv4 from ifconfig/ip
if [ -z "$IP" ]; then
  if command -v ip >/dev/null 2>&1; then
    IP=$(ip -4 addr show | awk '/inet /{print $2}' | cut -d/ -f1 | awk '($1 ~ /^10\./) || ($1 ~ /^192\.168\./) || ($1 ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) {print; exit}')
  else
    IP=$(ifconfig | awk '/inet /{print $2}' | awk '($1 ~ /^10\./) || ($1 ~ /^192\.168\./) || ($1 ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) {print; exit}')
  fi
fi

if [ -z "$IP" ]; then
  echo "Could not detect a private LAN IP automatically. Leaving SERVER_PUBLIC_URL unchanged." >&2
  exit 0
fi

PORT=$(get_env PORT)
if [ -z "$PORT" ]; then PORT=3000; fi
FORCE_SSL=$(get_env FORCE_SSL)
PROTO="http"
FORCE_SSL_LC=$(printf '%s' "$FORCE_SSL" | tr '[:upper:]' '[:lower:]')
if [ "$FORCE_SSL_LC" = "true" ] || [ "$FORCE_SSL_LC" = "1" ] || [ "$FORCE_SSL_LC" = "yes" ]; then PROTO="https"; fi

PORT_PART=":$PORT"
if { [ "$PROTO" = "http" ] && [ "$PORT" = "80" ]; } || { [ "$PROTO" = "https" ] && [ "$PORT" = "443" ]; }; then
  PORT_PART=""
fi

URL="${PROTO}://${IP}${PORT_PART}"
set_env_if_empty SERVER_PUBLIC_URL "$URL"

echo "Detected SERVER_PUBLIC_URL=$URL"
