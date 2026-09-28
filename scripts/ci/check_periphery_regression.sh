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
# No --depth: a shallow fetch grafts the repo and breaks the revision walk
# below. Same fix as .github/workflows/security.yml and lint_changed_swift.sh.
git fetch origin "$BASE_REF"

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

# Block on findings that sit on lines this branch actually changed, not on
# every finding in any file it touched.
#
# The step is called "new issues only" and it was not. It matched a filename
# against the whole report, so editing one line of a file that already had
# dead code failed the gate for that pre-existing code. Measured on the PR
# that exposed this: 3 findings on changed lines, 57 pre-existing ones in the
# same files — 47 of those in Theme.swift's design tokens, which no branch
# could ever be expected to clear before touching a colour.
#
# Changed lines are the same rule scripts/ci/lint_changed_swift.sh applies to
# SwiftLint, so the two gates now agree on what "new" means. Whole-file dead
# code stays visible in the advisory report uploaded by the previous step.
changed_lines="$(git diff -U0 "$DIFF_RANGE" -- '*.swift' \
  | awk '/^\+\+\+ b\//{f=substr($0,7)}
         /^@@/{ split($3,a,","); s=substr(a[1],2)+0; n=(a[2]==""?1:a[2])+0;
                for(i=0;i<n;i++) print f":"(s+i) }')"

found_new_issue=0

while IFS= read -r finding; do
  [[ -z "$finding" ]] && continue
  # Periphery's xcode output may carry absolute paths; keep the repo-relative tail.
  rel="${finding#"$(git rev-parse --show-toplevel)/"}"
  rel="${rel#./}"
  if grep -Fxq "$rel" <<< "$changed_lines"; then
    echo "New dead-code finding on a changed line: $rel"
    found_new_issue=1
  fi
done < <(grep -oE '^[^:]+\.swift:[0-9]+' "$REPORT_FILE" || true)

if [[ "$found_new_issue" -ne 0 ]]; then
  echo "Periphery regression gate failed: new dead-code findings on changed lines."
  exit 1
fi

echo "Periphery regression gate passed: no dead-code findings on changed lines."
