#!/usr/bin/env bash
#
# assert_ios_build_specs.sh  (spec 025 R2)
#
# Fails unless the tree matches the online iOS merge-CI contract:
#   - Xcode major >= 26 (Foundation Models SDK present to compile)
#   - scheme MeetMemento exists
#   - every IPHONEOS_DEPLOYMENT_TARGET >= 26.0
#   - destination env is reported (caller supplies IOS_SIM_DESTINATION)
#
# Usage: scripts/ci/assert_ios_build_specs.sh
# Portable: macOS Bash 3.2 + Linux Bash 4+.
set -euo pipefail

PBXPROJ="${PBXPROJ:-MeetMemento.xcodeproj/project.pbxproj}"
SCHEME="${SCHEME:-MeetMemento}"
MIN_XCODE_MAJOR="${MIN_XCODE_MAJOR:-26}"
MIN_DEPLOYMENT="${MIN_DEPLOYMENT:-26.0}"
IOS_SIM_DESTINATION="${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}"

fail=0
note() { echo "  $*"; }

version_lt() {
  # True if $1 < $2 (sort -V order).
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

[ -f "$PBXPROJ" ] || { echo "FAIL: pbxproj not found: $PBXPROJ"; exit 1; }

# --- Xcode major -------------------------------------------------------------
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "FAIL: xcodebuild not on PATH (DEVELOPER_DIR=${DEVELOPER_DIR:-unset})"
  exit 1
fi

xcode_line="$(xcodebuild -version | head -n1)"
echo "OK   toolchain: $xcode_line"
xcode_major="$(printf '%s\n' "$xcode_line" | sed -E 's/^Xcode[[:space:]]+([0-9]+).*/\1/')"
if ! [[ "$xcode_major" =~ ^[0-9]+$ ]]; then
  echo "FAIL: could not parse Xcode major version from: $xcode_line"
  fail=1
elif [ "$xcode_major" -lt "$MIN_XCODE_MAJOR" ]; then
  echo "FAIL: Xcode $xcode_major < required $MIN_XCODE_MAJOR (Foundation Models SDK)"
  note "Online CI compiles the Intelligence boundary; it does not require a provisioned model."
  fail=1
else
  echo "OK   Xcode major $xcode_major >= $MIN_XCODE_MAJOR"
fi

# --- Scheme ------------------------------------------------------------------
if xcodebuild -list -project MeetMemento.xcodeproj 2>/dev/null | grep -Eq "^[[:space:]]*${SCHEME}$"; then
  echo "OK   scheme $SCHEME present"
else
  echo "FAIL: scheme $SCHEME not found in MeetMemento.xcodeproj"
  fail=1
fi

# --- Deployment target -------------------------------------------------------
deploy_targets="$(grep -oE 'IPHONEOS_DEPLOYMENT_TARGET = [^;]+' "$PBXPROJ" \
  | sed -E 's/.*= //; s/[[:space:]]//g' | sort -u)"
if [ -z "$deploy_targets" ]; then
  echo "FAIL: no IPHONEOS_DEPLOYMENT_TARGET in $PBXPROJ"
  fail=1
else
  deploy_ok=1
  for ver in $deploy_targets; do
    if version_lt "$ver" "$MIN_DEPLOYMENT"; then
      echo "FAIL: IPHONEOS_DEPLOYMENT_TARGET=$ver < $MIN_DEPLOYMENT"
      deploy_ok=0
      fail=1
    fi
  done
  if [ "$deploy_ok" -eq 1 ]; then
    echo "OK   IPHONEOS_DEPLOYMENT_TARGET >= $MIN_DEPLOYMENT ($deploy_targets)"
  fi
fi

# --- Destination / online policy --------------------------------------------
echo "OK   destination: $IOS_SIM_DESTINATION"
echo "OK   online contract: UITests + device-gated FM generation skipped (CI_ONLINE=1)"

if [ "$fail" -ne 0 ]; then
  echo "FAIL [spec 025]: iOS build specifications not met."
  exit 1
fi
echo "OK [spec 025]: iOS build specifications satisfied."
