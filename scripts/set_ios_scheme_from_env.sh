#!/usr/bin/env bash
set -euo pipefail

# Sync iOS Info.plist URL scheme from APP_URL_SCHEME in .env
# Usage: scripts/set_ios_scheme_from_env.sh

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
PLIST="$ROOT_DIR/ios/Resources/Info.plist"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$PLIST" ]; then
  echo "Info.plist not found at $PLIST" >&2
  exit 1
fi

# Prefer .env; fallback to .env.example
if [ ! -f "$ENV_FILE" ] && [ -f "$ROOT_DIR/.env.example" ]; then
  ENV_FILE="$ROOT_DIR/.env.example"
fi

SCHEME="heyhouston"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC2002
  LINE=$(cat "$ENV_FILE" | grep -E '^APP_URL_SCHEME=' | tail -n1 || true)
  if [ -n "$LINE" ]; then
    SCHEME=${LINE#APP_URL_SCHEME=}
  fi
fi

if [ -z "$SCHEME" ]; then
  echo "APP_URL_SCHEME is empty; leaving Info.plist unchanged" >&2
  exit 0
fi

# Write scheme into Info.plist CFBundleURLTypes[0].CFBundleURLSchemes[0]
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string $SCHEME" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $SCHEME" "$PLIST"

echo "Updated iOS URL scheme in Info.plist to: $SCHEME"
