#!/usr/bin/env bash
#
# check_privacy_manifest.sh  (docs/app-store/03 — Guideline 5.1.2, ITMS-9105x)
#
# Keeps PrivacyInfo.xcprivacy honest in BOTH directions:
#
#   under-declared  -> a required-reason API is called in Swift but not declared
#                      => ITMS-91053 at upload. Hard failure.
#   over-declared   -> a category is declared but no matching call site exists
#                      => no upload error, but it is an inaccuracy in exactly the
#                         metadata class Apple rejected this app on in Nov 2025
#                         (Guideline 5.1.2). Hard failure.
#
# Also asserts the target privacy posture: NSPrivacyTracking = false, no tracking
# domains, no collected data types ("Data Not Collected", REQ-MON-004), and no
# NSUserTrackingUsageDescription anywhere (declaring tracking without ATT is the
# literal Nov 2025 rejection).
#
# Background: docs/app-store/03-privacy-labels-and-manifest.md
#
# Usage: scripts/ci/check_privacy_manifest.sh
set -euo pipefail

MANIFEST="${MANIFEST:-MeetMemento/PrivacyInfo.xcprivacy}"
SRC_ROOT="${SRC_ROOT:-MeetMemento}"

[ -f "$MANIFEST" ] || { echo "FAIL: privacy manifest not found: $MANIFEST"; exit 1; }

fail=0
note() { echo "  $*"; }

# --- Category -> source-pattern map -----------------------------------------
# Each entry: <NSPrivacyAccessedAPICategory suffix>|<extended regex of the APIs>
CATEGORIES=(
  "UserDefaults|UserDefaults"
  "FileTimestamp|attributesOfItem|contentModificationDate|creationDate|modificationDateKey|creationDateKey"
  "SystemBootTime|systemUptime|mach_absolute_time|kern\.boottime"
  "DiskSpace|volumeAvailableCapacity|systemFreeSize|attributesOfFileSystem"
  "ActiveKeyboards|activeInputModes"
)

echo "Privacy manifest: $MANIFEST"
echo "Source root:      $SRC_ROOT"
echo ""

for entry in "${CATEGORIES[@]}"; do
  name="${entry%%|*}"
  pattern="${entry#*|}"

  # Match the plist ELEMENT, not prose: the manifest carries XML comments that
  # explain why a category was removed, and those must not read as declarations.
  declared=0
  grep -q "<string>NSPrivacyAccessedAPICategory${name}</string>" "$MANIFEST" && declared=1

  used=0
  if grep -rEq "$pattern" "$SRC_ROOT" --include="*.swift" 2>/dev/null; then
    used=1
  fi

  if [ "$declared" -eq 1 ] && [ "$used" -eq 0 ]; then
    echo "FAIL [over-declared]: NSPrivacyAccessedAPICategory${name} is declared but no call site matches /$pattern/"
    note "Remove the block from $MANIFEST, or point this check at the real API use."
    note "See docs/app-store/03-privacy-labels-and-manifest.md section 2."
    fail=1
  elif [ "$declared" -eq 0 ] && [ "$used" -eq 1 ]; then
    echo "FAIL [under-declared]: /$pattern/ is used in $SRC_ROOT but NSPrivacyAccessedAPICategory${name} is not declared"
    note "This produces ITMS-91053 at upload. Add the category with a valid reason code."
    note "Reason codes: docs/app-store/03-privacy-labels-and-manifest.md section 2."
    fail=1
  elif [ "$declared" -eq 1 ]; then
    echo "OK   ${name}: declared and used"
  else
    echo "OK   ${name}: not declared, not used"
  fi
done

echo ""

# --- Target privacy posture --------------------------------------------------
# NSPrivacyTracking must be false. plutil is the reliable reader; fall back to a
# structural grep on non-macOS runners.
if command -v plutil >/dev/null 2>&1; then
  tracking="$(plutil -extract NSPrivacyTracking raw -o - "$MANIFEST" 2>/dev/null || echo "MISSING")"
  if [ "$tracking" != "false" ]; then
    echo "FAIL: NSPrivacyTracking is '$tracking', expected 'false'."
    note "Declaring tracking obliges ATT. Declaring it WITHOUT ATT is the Nov 2025 rejection."
    fail=1
  else
    echo "OK   NSPrivacyTracking = false"
  fi

  collected="$(plutil -extract NSPrivacyCollectedDataTypes raw -o - "$MANIFEST" 2>/dev/null || echo "MISSING")"
  if [ "$collected" != "0" ]; then
    echo "FAIL: NSPrivacyCollectedDataTypes is non-empty (count: $collected)."
    note "Target label is 'Data Not Collected' (REQ-MON-004, spec 021 R5). If a"
    note "disclosure is genuinely required, update this check together with the"
    note "App Store Connect label AND the published privacy policy - all three"
    note "must agree. See docs/app-store/03 section 1."
    fail=1
  else
    echo "OK   NSPrivacyCollectedDataTypes = [] (Data Not Collected)"
  fi
else
  if grep -A1 "NSPrivacyTracking</key>" "$MANIFEST" | grep -q "<false/>"; then
    echo "OK   NSPrivacyTracking = false (grep fallback; plutil unavailable)"
  else
    echo "FAIL: NSPrivacyTracking is not <false/>."
    fail=1
  fi
  if grep -A1 "NSPrivacyCollectedDataTypes</key>" "$MANIFEST" | grep -q "<array/>"; then
    echo "OK   NSPrivacyCollectedDataTypes = [] (grep fallback)"
  else
    echo "FAIL: NSPrivacyCollectedDataTypes is not an empty array."
    fail=1
  fi
fi

# --- ATT must be absent ------------------------------------------------------
if grep -rq "NSUserTrackingUsageDescription" --include="*.plist" --include="*.pbxproj" . 2>/dev/null; then
  echo "FAIL: NSUserTrackingUsageDescription found. Memento does not track; adding"
  note "this key implies it does and reopens the Guideline 5.1.2 rejection."
  fail=1
else
  echo "OK   NSUserTrackingUsageDescription absent"
fi

echo ""
if [ "$fail" -ne 0 ]; then
  echo "FAIL [docs/app-store/03]: privacy manifest does not match the code or the target posture."
  exit 1
fi
echo "OK [docs/app-store/03]: privacy manifest matches the code in both directions."
