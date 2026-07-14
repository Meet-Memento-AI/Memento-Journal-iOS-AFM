#!/bin/bash
#
# assert_release_endpoint.sh  (spec 006 / R3)
#
# Fails if a Release build's resolved SUPABASE_URL is a placeholder, empty, or
# lacks a real host. Guards against shipping/archiving an app pointed at a dev
# endpoint or at the literal template value (the //-comment truncation that spec
# 002 fixed would surface here as a missing host).
#
# Two entry points, one logic:
#   * Xcode Release build phase — $SUPABASE_URL is already in the environment; this
#     script is a no-op for non-Release configs (guarded by the phase itself).
#   * CI / manual — resolves the value via `xcodebuild -showBuildSettings`.
#
# Usage: scripts/ci/assert_release_endpoint.sh [configuration]
#   configuration defaults to "Release".
set -euo pipefail

CONFIG="${CONFIGURATION:-${1:-Release}}"

if [ -n "${SUPABASE_URL:-}" ]; then
  # Build-phase context: value is already resolved in the environment.
  URL=$(printf '%s' "$SUPABASE_URL" | tr -d '[:space:]')
else
  PROJECT="MeetMemento.xcodeproj"
  SCHEME="MeetMemento"
  URL=$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" 2>/dev/null \
    | awk -F' = ' '/ SUPABASE_URL = /{print $2; exit}' \
    | tr -d '[:space:]')
fi

echo "Resolved SUPABASE_URL ($CONFIG): '${URL}'"

if [ -z "$URL" ]; then
  echo "::error::SUPABASE_URL is empty for the $CONFIG configuration. Create MeetMemento/Config/${CONFIG}.local.xcconfig from the template with real values."
  exit 1
fi

case "$URL" in
  *YOUR_PROJECT_ID*|*your-project-id*|*YOUR_SUPABASE*|*placeholder*|*xxxxx*|*invalid.supabase*)
    echo "::error::SUPABASE_URL is still a placeholder ('$URL'). A Release build must point at the production Supabase project."
    exit 1
    ;;
esac

# Must be https with a real supabase.co host (also catches the //-comment truncation
# to 'https:' that would leave no host).
if ! printf '%s' "$URL" | grep -Eq '^https://[a-z0-9-]+\.supabase\.co/?$'; then
  echo "::error::SUPABASE_URL '$URL' is not a valid https://<project>.supabase.co URL."
  exit 1
fi

echo "OK: $CONFIG SUPABASE_URL is a real production endpoint."
