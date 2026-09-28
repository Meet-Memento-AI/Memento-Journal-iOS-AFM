#!/usr/bin/env bash
#
# check_archive_hygiene.sh  (docs/app-store/07 s6)
#
# The Release bundle has shipped junk before: spec 002 finding #7 found SQL
# migrations, xcconfigs, internal markdown, a loose SVG, and a .storekit test
# configuration inside the built app. Shipping schema and internal docs in the
# binary is information disclosure and submission noise.
#
# The withMemento/ group is a PBXFileSystemSynchronizedRootGroup: every file in
# the folder is a target member UNLESS it is listed individually in the
# membershipExceptions set. Directory-level exceptions DO NOT WORK (spec 002
# task 9) - so any newly added doc/config/fixture silently starts shipping.
#
# This check asserts that every file matching a non-shippable pattern is in the
# exception set.
#
# It also reports placeholder StoreKit product identifiers. That is REPORT-ONLY
# today because DEC-004 (pricing) is open and no paywall exists; it must become
# a hard gate before Gate S, since Guideline 2.1(b) requires in-app purchases to
# be complete, visible to the reviewer, and functional.
#
# Usage: scripts/ci/check_archive_hygiene.sh
#   STOREKIT_ENFORCE=1 -> placeholder product ids fail the build
set -euo pipefail

PBXPROJ="${PBXPROJ:-withMemento.xcodeproj/project.pbxproj}"
APP_DIR="${APP_DIR:-withMemento}"
STOREKIT_ENFORCE="${STOREKIT_ENFORCE:-0}"

[ -f "$PBXPROJ" ] || { echo "FAIL: pbxproj not found: $PBXPROJ"; exit 1; }

fail=0
note() { echo "  $*"; }

# Extract the membershipExceptions block once, as one EXACT entry per line.
#
# Entries look like `Config/Debug.xcconfig,` or `"Preview Content/Foo.json",`.
# Strip the indentation, the trailing comma, and the optional quotes so the
# comparison below can be exact.
#
# 2026-09-12: this used to be a raw `grep -qF` against the whole block, which
# matched on SUBSTRINGS. `Config/Supabase.xcconfig` was therefore reported as
# excluded purely because `Config/Supabase.xcconfig.example` is in the set — the
# real xcconfig (the one holding the anon key) was never actually checked. A
# hygiene gate that can be satisfied by a prefix of a different filename is not
# a gate.
exceptions="$(awk '/membershipExceptions = \(/,/\);/' "$PBXPROJ" \
  | sed -e '1d' -e '$d' \
  | sed -e 's/^[[:space:]]*//' -e 's/,[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"

# Exact, whole-line membership test.
is_excluded() {
  printf '%s\n' "$exceptions" | grep -qxF "$1"
}

echo "Checking non-shippable files under $APP_DIR/ against membershipExceptions"
echo ""

# Patterns that must never ship inside the app bundle.
#   -name matches, evaluated relative to $APP_DIR.
missing=()
while IFS= read -r path; do
  rel="${path#"$APP_DIR"/}"
  base="$(basename "$rel")"
  # A file is excluded if its target-relative path, or its bare basename, is an
  # EXACT entry in the set. Xcode writes whichever form the group nesting
  # produces, so both are accepted — but neither is accepted as a substring.
  if is_excluded "$rel" || is_excluded "$base"; then
    continue
  fi
  missing+=("$rel")
done < <(find "$APP_DIR" \
  -path "*.xcassets/*" -prune -o \
  \( -name "*.md" \
  -o -name "*.storekit" \
  -o -name "*.xcconfig" \
  -o -name "*.xcconfig.template" \
  -o -name "*.sql" \
  -o -name "*.svg" \
  -o -name "PreviewMocks.json" \
  -o -name "*.toml" \) \
  -type f -print 2>/dev/null | sort)

if [ "${#missing[@]}" -gt 0 ]; then
  echo "FAIL: these files are NOT in membershipExceptions and will ship in the app bundle:"
  for m in "${missing[@]}"; do echo "  - $APP_DIR/$m"; done
  note ""
  note "Add each one INDIVIDUALLY to the exception set in Xcode (directory-level"
  note "exceptions do not work). See docs/app-store/07 section 6."
  fail=1
else
  echo "OK   every doc/config/fixture under $APP_DIR/ is excluded from the target"
fi

# --- Placeholder StoreKit product identifiers --------------------------------
echo ""
storekit_files="$(find "$APP_DIR" -name "*.storekit" -type f 2>/dev/null || true)"
if [ -z "$storekit_files" ]; then
  echo "OK   no .storekit configuration in the project"
else
  placeholders=""
  for f in $storekit_files; do
    if grep -qE '"(12345678|123456789|com\.example|REPLACE_ME)"' "$f"; then
      placeholders="$placeholders $f"
    fi
  done
  if [ -n "$placeholders" ]; then
    echo "[Guideline 2.1(b)] placeholder product identifiers found in:$placeholders"
    note "In-app purchases must be complete, visible to the reviewer, and"
    note "functional. Replace with the real App Store Connect product ids once"
    note "DEC-004 (spec 021 R1) resolves."
    if [ "$STOREKIT_ENFORCE" = "1" ]; then
      echo "FAIL (STOREKIT_ENFORCE=1)."
      fail=1
    else
      echo "REPORT-ONLY (STOREKIT_ENFORCE=0): must be a hard gate before Gate S."
    fi
  else
    echo "OK   no placeholder product identifiers"
  fi
fi

echo ""
if [ "$fail" -ne 0 ]; then
  echo "FAIL [docs/app-store/07 s6]: archive hygiene checks did not pass."
  exit 1
fi
echo "OK [docs/app-store/07 s6]: archive hygiene checks passed."
