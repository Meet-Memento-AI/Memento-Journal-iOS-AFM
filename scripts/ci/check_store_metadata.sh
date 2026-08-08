#!/usr/bin/env bash
#
# check_store_metadata.sh  (docs/app-store/02, /07)
#
# Guards the Info.plist / project settings that App Store Connect itself checks,
# and that this project has already gotten wrong once:
#
#   1. ITSAppUsesNonExemptEncryption present  -> otherwise every upload prompts
#      for export compliance (spec 002 R1).
#   2. All three usage-description keys present and non-boilerplate -> Apple's
#      own common-rejection #6 is unclear data-access requests.
#   3. Usage strings defined EXACTLY ONCE -> GENERATE_INFOPLIST_FILE = YES merges
#      Info.plist with INFOPLIST_KEY_* build settings and the winner is
#      unpredictable (spec 002 R5).
#   4. No com.testing.* bundle ids -> sample targets were removed by spec 002 R4.
#   5. Build number above the last-uploaded floor -> 1.0(2) was uploaded and
#      rejected in Nov 2025; build numbers are consumed permanently per version
#      string, so reusing one is ITMS-90062 territory (docs/app-store/07 s2).
#
# Usage: scripts/ci/check_store_metadata.sh
set -euo pipefail

PLIST="${PLIST:-MeetMemento/Info.plist}"
PBXPROJ="${PBXPROJ:-MeetMemento.xcodeproj/project.pbxproj}"
UPLOADED="${UPLOADED:-docs/app-store/last-uploaded-build.txt}"

[ -f "$PLIST" ] || { echo "FAIL: Info.plist not found: $PLIST"; exit 1; }
[ -f "$PBXPROJ" ] || { echo "FAIL: pbxproj not found: $PBXPROJ"; exit 1; }

fail=0
note() { echo "  $*"; }

# --- 1. Export compliance ----------------------------------------------------
if grep -q "ITSAppUsesNonExemptEncryption" "$PLIST"; then
  echo "OK   ITSAppUsesNonExemptEncryption present"
else
  echo "FAIL: ITSAppUsesNonExemptEncryption missing from $PLIST"
  note "Without it every App Store Connect upload asks the export-compliance"
  note "question. See docs/app-store/05 section 3."
  fail=1
fi

# --- 2 & 3. Usage descriptions ----------------------------------------------
# Boilerplate strings draw Guideline 5.1.1 rejections; require a minimum length
# and the app's name, which forces a specific sentence rather than "This app
# needs microphone access".
REQUIRED_KEYS=(
  NSFaceIDUsageDescription
  NSMicrophoneUsageDescription
  NSSpeechRecognitionUsageDescription
)

for key in "${REQUIRED_KEYS[@]}"; do
  if ! grep -q "<key>${key}</key>" "$PLIST"; then
    echo "FAIL: ${key} missing from $PLIST"
    fail=1
    continue
  fi

  # Duplicate definition in build settings?
  if grep -q "INFOPLIST_KEY_${key}" "$PBXPROJ"; then
    echo "FAIL: ${key} is defined in BOTH $PLIST and INFOPLIST_KEY_${key} in the project."
    note "GENERATE_INFOPLIST_FILE = YES merges them and the winner is unpredictable."
    note "Keep the string in Info.plist only (spec 002 R5)."
    fail=1
    continue
  fi

  value="$(grep -A1 "<key>${key}</key>" "$PLIST" | tail -1 | sed -E 's#.*<string>(.*)</string>.*#\1#')"
  if [ "${#value}" -lt 30 ]; then
    echo "FAIL: ${key} looks like boilerplate (${#value} chars): \"$value\""
    note "Apple's common-rejection #6 is unclear data-access requests. State what"
    note "the data is used for. See docs/app-store/02 section 4."
    fail=1
  elif ! printf '%s' "$value" | grep -qi "memento"; then
    echo "FAIL: ${key} does not name the app: \"$value\""
    note "Purpose strings should be specific to this app, not generic."
    fail=1
  else
    echo "OK   ${key} present, specific, defined once"
  fi
done

# --- 4. No sample-target bundle ids ------------------------------------------
if grep -q "com\.testing\." "$PBXPROJ"; then
  echo "FAIL: com.testing.* bundle id found in the project."
  note "Sample/playground targets must never enter the archive (spec 002 R4)."
  fail=1
else
  echo "OK   no com.testing.* bundle ids"
fi

# --- 5. Build number floor ---------------------------------------------------
version="$(grep -m1 -oE 'MARKETING_VERSION = [^;]+' "$PBXPROJ" | sed -E 's/MARKETING_VERSION = //; s/[[:space:]]//g')"
build="$(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [^;]+' "$PBXPROJ" | sed -E 's/CURRENT_PROJECT_VERSION = //; s/[[:space:]]//g')"

if [ ! -f "$UPLOADED" ]; then
  echo "WARN no last-uploaded record at $UPLOADED; skipping the build-number floor check."
else
  # Format: "<version> <build>" per line, comments with #.
  floor=""
  while read -r v b _; do
    case "$v" in ''|\#*) continue ;; esac
    [ "$v" = "$version" ] && floor="$b"
  done < "$UPLOADED"

  if [ -z "$floor" ]; then
    echo "OK   version $version has no prior uploads recorded; build $build accepted"
  elif [ "$build" -le "$floor" ]; then
    echo "FAIL: version $version build $build was already uploaded (floor: $floor)."
    note "Build numbers are consumed permanently per version string, even by"
    note "builds that were rejected or deleted. Bump CURRENT_PROJECT_VERSION."
    note "See docs/app-store/07 section 2."
    fail=1
  else
    echo "OK   version $version build $build is above the uploaded floor ($floor)"
  fi
fi

echo ""
if [ "$fail" -ne 0 ]; then
  echo "FAIL [docs/app-store/02, /07]: store metadata checks did not pass."
  exit 1
fi
echo "OK [docs/app-store/02, /07]: store metadata checks passed."
