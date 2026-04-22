#!/usr/bin/env bash
set -euo pipefail

REPORT_FILE="${1:-periphery-report.txt}"
BASE_REF="${2:-${GITHUB_BASE_REF:-dev}}"

if [[ ! -f "$REPORT_FILE" ]]; then
  echo "Periphery report file not found: $REPORT_FILE"
  exit 1
fi

if [[ -z "$BASE_REF" ]]; then
  echo "No base ref provided, skipping periphery regression check."
  exit 0
fi

echo "Using base ref: $BASE_REF"
git fetch origin "$BASE_REF" --depth=1

changed_files=$(git diff --name-only "origin/$BASE_REF"...HEAD -- '*.swift' || true)

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
