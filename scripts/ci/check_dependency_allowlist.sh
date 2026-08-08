#!/usr/bin/env bash
#
# check_dependency_allowlist.sh  (spec 021 / R6 — REQ-MON-005)
#
# Diffs the resolved third-party SPM dependency set against the committed
# allowlist (specs/dependency-allowlist.txt). Any package identity not on the
# list is a violation naming REQ-MON-005 and spec 021.
#
# MODE (spec 021 R6 sequencing note): the product is on-device only. Only the two
# UI packages (ProgressiveBlurHeader, SVGKit) remain outside the TARGET allowlist
# (RevenueCat only), so this runs REPORT-ONLY by default (warns, exits 0). Once
# those two get a REQ-MON-005 decision record or are removed, flip to enforcing:
# ALLOWLIST_ENFORCE=1 (must be a hard gate before spec 021 closes).
#
# Usage: scripts/ci/check_dependency_allowlist.sh
#   ALLOWLIST_ENFORCE=1  -> violations fail the build (default: report-only)
set -euo pipefail

ALLOWLIST_FILE="${ALLOWLIST_FILE:-specs/dependency-allowlist.txt}"
PBXPROJ="${PBXPROJ:-MeetMemento.xcodeproj/project.pbxproj}"
ENFORCE="${ALLOWLIST_ENFORCE:-0}"

[ -f "$ALLOWLIST_FILE" ] || { echo "Allowlist not found: $ALLOWLIST_FILE"; exit 1; }
[ -f "$PBXPROJ" ] || { echo "pbxproj not found: $PBXPROJ"; exit 1; }

normalize() { # https://github.com/Owner/Repo(.git) -> owner/repo
  sed -E 's#\.git$##; s#^.*github\.com[:/]##; s#^https?://[^/]+/##' | tr '[:upper:]' '[:lower:]'
}

# Allowed identities (strip comments/blanks).
allowed=()
while IFS= read -r a; do
  [ -z "$a" ] && continue
  allowed+=("$a")
done < <(grep -vE '^[[:space:]]*#' "$ALLOWLIST_FILE" | grep -vE '^[[:space:]]*$' | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+//g')

# Resolved third-party packages from the project's remote package references.
resolved=()
while IFS= read -r r; do
  [ -z "$r" ] && continue
  resolved+=("$r")
done < <(grep -oE 'repositoryURL = "[^"]+"' "$PBXPROJ" | sed -E 's/repositoryURL = "([^"]+)"/\1/' | normalize | sort -u)

echo "Allowlist ($ALLOWLIST_FILE): ${allowed[*]:-<empty>}"
echo "Resolved third-party SPM packages:"
for r in "${resolved[@]:-}"; do [ -n "$r" ] && echo "  - $r"; done

violations=()
for r in "${resolved[@]:-}"; do
  [ -z "$r" ] && continue
  ok=0
  for a in "${allowed[@]:-}"; do [ "$r" = "$a" ] && ok=1 && break; done
  [ "$ok" -eq 0 ] && violations+=("$r")
done

if [ "${#violations[@]}" -gt 0 ]; then
  echo ""
  echo "[REQ-MON-005 / spec 021 R6] packages NOT on the allowlist:"
  for v in "${violations[@]}"; do echo "  - $v"; done
  if [ "$ENFORCE" = "1" ]; then
    echo "FAIL: add a decision record to spec 021 and update $ALLOWLIST_FILE, or remove the dependency."
    exit 1
  fi
  echo "REPORT-ONLY (ALLOWLIST_ENFORCE=0): not failing. These must be resolved before spec 021 closes."
  exit 0
fi

echo ""
echo "OK [REQ-MON-005 / spec 021 R6]: all third-party packages are on the allowlist."
