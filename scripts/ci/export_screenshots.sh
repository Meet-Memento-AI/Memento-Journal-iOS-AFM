#!/usr/bin/env bash
#
# export_screenshots.sh  (docs/app-store/04 §5, checklist D9)
#
# Lifts the App Store frames out of an xcresult bundle into
# docs/app-store/metadata/en-US/screenshots/<slot>/ and verifies each one's
# pixel dimensions.
#
# The verification is the point. A screenshot run can pass, attach the right
# number of files at the right size, and still be wrong — the first version of
# AppStoreScreenshotUITests guessed navigation identifiers that did not exist,
# so the taps were no-ops and two "frames" were byte-identical copies of the
# timeline. Count and dimensions both looked correct. So this also checks that
# the frames are distinct, which is the cheapest proxy for "navigation actually
# happened".
#
# Usage:
#   scripts/ci/export_screenshots.sh <result.xcresult> <slot> <WIDTHxHEIGHT>
#   scripts/ci/export_screenshots.sh shots.xcresult iphone-6.9 1320x2868
set -euo pipefail

BUNDLE="${1:?usage: export_screenshots.sh <result.xcresult> <slot> <WxH>}"
SLOT="${2:?slot, e.g. iphone-6.9 or ipad-13}"
EXPECTED="${3:?expected dimensions, e.g. 1320x2868}"
OUT="docs/app-store/metadata/en-US/screenshots/$SLOT"

[ -d "$BUNDLE" ] || { echo "FAIL: no such result bundle: $BUNDLE"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$TMP" >/dev/null

mkdir -p "$OUT"
fail=0
count=0

# The manifest maps the attachment's human-readable name (01-timeline.png) to
# the exported UUID filename.
while IFS=$'\t' read -r name file; do
  [ -z "$name" ] && continue
  # name is like 01-timeline_0_<uuid>.png — keep the slug, restore the suffix.
  dst="$OUT/${name%%_*}.png"
  cp "$TMP/$file" "$dst"
  dims="$(sips -g pixelWidth -g pixelHeight "$dst" \
    | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
  if [ "$dims" = "$EXPECTED" ]; then
    echo "OK   $(basename "$dst")  $dims"
  else
    echo "FAIL $(basename "$dst")  $dims (expected $EXPECTED)"
    fail=1
  fi
  count=$((count + 1))
done < <(python3 - "$TMP/manifest.json" <<'PY'
import json, sys
def walk(o, out):
    if isinstance(o, dict):
        for a in o.get("attachments", []) or []:
            n = a.get("suggestedHumanReadableName", "")
            if n[:1].isdigit() and n.endswith(".png"):
                out.append((n, a["exportedFileName"]))
        for v in o.values():
            walk(v, out)
    elif isinstance(o, list):
        for v in o:
            walk(v, out)
rows = []
walk(json.load(open(sys.argv[1])), rows)
for n, f in sorted(rows):
    print(f"{n}\t{f}")
PY
)

[ "$count" -gt 0 ] || { echo "FAIL: no numbered frames in $BUNDLE"; exit 1; }

# Distinctness: duplicates mean a navigation step silently did nothing.
uniq_count="$(shasum -a 256 "$OUT"/*.png | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"
if [ "$uniq_count" -ne "$count" ]; then
  echo "FAIL: $count frames but only $uniq_count distinct — a navigation step was a no-op"
  fail=1
else
  echo "OK   $count frames, all distinct"
fi

[ "$fail" -eq 0 ] || { echo; echo "FAIL [04 §5 / D9]: screenshot export did not pass."; exit 1; }
echo
echo "OK [04 §5 / D9]: $count frames in $OUT at $EXPECTED."
