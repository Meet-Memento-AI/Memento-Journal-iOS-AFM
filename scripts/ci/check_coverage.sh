#!/usr/bin/env bash
set -euo pipefail

RESULT_BUNDLE_PATH="${1:-TestResults.xcresult}"
MIN_COVERAGE="${MIN_COVERAGE:-60}"

if [[ ! -d "$RESULT_BUNDLE_PATH" ]]; then
  echo "Coverage result bundle not found at $RESULT_BUNDLE_PATH"
  exit 1
fi

COVERAGE_PERCENT=$(xcrun xccov view --report --json "$RESULT_BUNDLE_PATH" | python3 -c '
import json,sys
report = json.load(sys.stdin)
line = report.get("lineCoverage")
if line is None:
    targets = report.get("targets", [])
    if targets:
        line = targets[0].get("lineCoverage")
if line is None:
    print("0.00")
else:
    print(f"{line*100:.2f}")
')

echo "Measured line coverage: ${COVERAGE_PERCENT}%"

echo "Required minimum coverage: ${MIN_COVERAGE}%"

awk -v actual="$COVERAGE_PERCENT" -v min="$MIN_COVERAGE" 'BEGIN {
  if (actual + 0 < min + 0) {
    printf("Coverage gate failed: %.2f%% < %.2f%%\n", actual, min)
    exit 1
  }
  printf("Coverage gate passed: %.2f%% >= %.2f%%\n", actual, min)
}'
