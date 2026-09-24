#!/usr/bin/env bash
set -euo pipefail

REPORT_FILE="${1:-periphery-report.txt}"
BASE_REF="${2:-${GITHUB_BASE_REF:-dev}}"
EXIT_FILE="${3:-${REPORT_FILE%.*}-exit.txt}"

if [[ ! -f "$REPORT_FILE" ]]; then
  echo "Periphery report file not found: $REPORT_FILE"
  exit 1
fi

# The scan step is `continue-on-error`, so a crashed or killed scan still leaves
# an empty report behind — and an empty report grepped for new findings in
# changed files finds none and reports success. That is a gate that stops
# gating the moment the tool breaks, which is the failure this repo already
# paid for once in `hall.fabricatedQuote` (046 R1): a check that cannot run
# must fail, never pass quietly.
#
# So the scan's exit status is load-bearing. If the file is absent we cannot
# tell a clean scan from a broken one, and the safe reading of an unknown is
# failure.
if [[ -f "$EXIT_FILE" ]]; then
  scan_exit="$(tr -d '[:space:]' < "$EXIT_FILE")"
  if [[ "$scan_exit" != "0" ]]; then
    echo "Periphery scan exited $scan_exit — the report cannot be trusted."
    echo "Refusing to report a pass from a scan that did not complete."
    exit 1
  fi
else
  echo "No scan exit-status file ($EXIT_FILE)."
  echo "Cannot distinguish a clean scan from a failed one; failing closed."
  exit 1
fi

if [[ -z "$BASE_REF" ]]; then
  echo "No base ref provided, skipping periphery regression check."
  exit 0
fi

echo "Using base ref: $BASE_REF"
git fetch origin "$BASE_REF" --depth=1

if git merge-base "origin/$BASE_REF" HEAD >/dev/null 2>&1; then
  DIFF_RANGE="origin/$BASE_REF...HEAD"
else
  DIFF_RANGE="origin/$BASE_REF..HEAD"
fi

changed_files=$(git diff --name-only "$DIFF_RANGE" -- '*.swift' || true)

if [[ -z "$changed_files" ]]; then
  echo "No Swift file changes detected relative to $BASE_REF."
  exit 0
fi

echo "Swift files changed relative to $BASE_REF:"
echo "$changed_files"

found_new_issue=0

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Periphery xcode output may include absolute paths. Match both relative and absolute suffixes.
  if grep -Fq "$file:" "$REPORT_FILE" || grep -Fq "/$file:" "$REPORT_FILE"; then
    echo "New dead-code issue references changed file: $file"
    found_new_issue=1
  fi
done <<< "$changed_files"

if [[ "$found_new_issue" -ne 0 ]]; then
  echo "Periphery regression gate failed: new dead-code findings detected in changed files."
  exit 1
fi

echo "Periphery regression gate passed: no new dead-code findings in changed files."
