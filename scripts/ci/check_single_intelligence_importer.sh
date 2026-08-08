#!/usr/bin/env bash
#
# check_single_intelligence_importer.sh  (spec 017 / R1 — REQ-INT-001, P3)
#
# Architecture principle P3 / CONSTITUTION.md §4 rule 5: EXACTLY ONE Swift module
# imports FoundationModels; every other module depends on the IntelligenceService
# protocol. This is the "checkable by build configuration, not just code review"
# floor the spec's Regression Guards demand.
#
# Enforcement is `count <= MAX` (default 1):
#   * Before spec 017 lands, the intelligence module doesn't exist yet -> count 0 -> pass.
#   * Once it lands, count 1 -> pass.
#   * A second importer anywhere -> count 2 -> FAIL (FoundationModels is leaking).
# Set INTELLIGENCE_IMPORTER_EXPECT_EXACTLY=1 after 017 lands to also catch an
# accidental REMOVAL (count 0) of the single importer.
#
# Note: `#if canImport(FoundationModels)` availability guards are NOT imports and
# are intentionally not matched. (The Liquid Glass code no longer uses such
# guards — spec 024 removed them when it adopted native `.glassEffect` directly;
# any remaining guards belong to genuine FoundationModels-gated code.)
#
# Usage: scripts/ci/check_single_intelligence_importer.sh
set -euo pipefail

MAX="${INTELLIGENCE_IMPORTER_MAX:-1}"
EXPECT_EXACTLY="${INTELLIGENCE_IMPORTER_EXPECT_EXACTLY:-0}"

roots=()
for d in MeetMemento MeetMementoTests MeetMementoUITests; do
  [ -d "$d" ] && roots+=("$d")
done

# A real `import FoundationModels` statement: anchored at line start (Swift
# imports are always column 0). This excludes `#if canImport(FoundationModels)`
# guards AND prose mentions of "import FoundationModels" inside comments.
importers=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  importers+=("$f")
done < <(grep -rlE --include='*.swift' '^import[[:space:]]+FoundationModels' "${roots[@]}" 2>/dev/null | sort -u || true)
count="${#importers[@]}"

echo "FoundationModels importers found: $count (max allowed: $MAX)"
for f in "${importers[@]:-}"; do [ -n "$f" ] && echo "  - $f"; done

if [ "$count" -gt "$MAX" ]; then
  echo ""
  echo "FAIL [REQ-INT-001 / spec 017 R1 / P3]: FoundationModels is imported by $count files;"
  echo "exactly one module (the intelligence boundary) may import it. Route the extra"
  echo "call site through the IntelligenceService protocol instead."
  exit 1
fi

if [ "$EXPECT_EXACTLY" = "1" ] && [ "$count" -ne 1 ]; then
  echo ""
  echo "FAIL [REQ-INT-001 / spec 017 R1]: expected exactly 1 FoundationModels importer"
  echo "(the intelligence module) but found $count. The single importer must not be removed."
  exit 1
fi

echo "OK [REQ-INT-001 / spec 017 R1 / P3]"
