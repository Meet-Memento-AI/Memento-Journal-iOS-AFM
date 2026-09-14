#!/usr/bin/env bash
#
# check_app_size.sh  (docs/app-store/00 C10)
#
# Guards the app bundle against silently crossing the 200 MB cellular-download
# threshold, above which iOS prompts before downloading over cellular.
#
# This needs a BUILD PRODUCT, so it belongs in ios-build-online.yml (macOS),
# not spec-gates.yml (Linux, no Xcode). It skips cleanly when no product is
# present so it can be run locally without ceremony.
#
# Usage:
#   scripts/ci/check_app_size.sh [path/to/MeetMemento.app]
#   APP_PATH=... scripts/ci/check_app_size.sh
set -euo pipefail

BUDGET="${BUDGET_FILE:-docs/app-store/app-size-budget.txt}"
[ -f "$BUDGET" ] || { echo "FAIL: budget file not found: $BUDGET"; exit 1; }

ceiling="$(awk '/^CEILING_MB[[:space:]]/ {print $2; exit}' "$BUDGET")"
if [ -z "${ceiling:-}" ]; then
  echo "FAIL: no 'CEILING_MB <number>' line in $BUDGET"
  exit 1
fi

app="${1:-${APP_PATH:-}}"
if [ -z "$app" ]; then
  # Prefer an archive product (closest to what ships), then any Release build.
  app="$(find build -name 'MeetMemento.app' -maxdepth 6 2>/dev/null | head -1 || true)"
  [ -z "$app" ] && app="$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Release*/MeetMemento.app' -maxdepth 5 2>/dev/null | head -1 || true)"
fi

if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "SKIP no MeetMemento.app found — build Release or pass a path."
  echo "     Ceiling on record: ${ceiling} MB (docs/app-store/00 C10)"
  exit 0
fi

# A bundle with no executable is a partial or failed build, and measuring it
# reports a PASS on a number that means nothing. Caught while building this
# gate: an interrupted build left a resources-only .app that measured 153 MB
# instead of 188 MB and sailed through. Refuse to grade an incomplete product.
exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist" 2>/dev/null || true)"
if [ -z "$exe" ] || [ ! -f "$app/$exe" ]; then
  echo "FAIL: $app has no executable ($app/${exe:-<unset CFBundleExecutable>})."
  echo "      That is a partial or failed build, not a bundle to measure."
  exit 1
fi

kb="$(du -sk "$app" | cut -f1)"
mb=$(( kb / 1024 ))

echo "Bundle:  $app"
echo "Size:    ${mb} MB"
echo "Ceiling: ${ceiling} MB"
echo ""
echo "Largest components:"
du -sk "$app"/* 2>/dev/null | sort -rn | head -6 \
  | awk '{ printf "  %7.1f MB  %s\n", $1/1024, $2 }'
echo ""

if [ "$mb" -gt "$ceiling" ]; then
  echo "FAIL [docs/app-store/00 C10]: bundle is ${mb} MB, over the ${ceiling} MB ceiling."
  echo ""
  echo "Above 200 MB iOS prompts before downloading over cellular. Either move"
  echo "the voice weights to on-demand resources / Background Assets (spec 030"
  echo "revisits DEC-012), or raise CEILING_MB in $BUDGET as a recorded decision"
  echo "with the conversion cost accepted in writing."
  exit 1
fi

headroom=$(( ceiling - mb ))
echo "OK [docs/app-store/00 C10]: ${mb} MB, ${headroom} MB under the ceiling."
