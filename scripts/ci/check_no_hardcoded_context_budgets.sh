#!/usr/bin/env bash
#
# check_no_hardcoded_context_budgets.sh  (spec 017 R9 / CONSTITUTION §4 rule 5)
#
# "Context budgeting is a contract, not a habit." The model's context window is
# a RUNTIME value (4096 on iOS 26, 8192 on iOS 27 newer devices on-device,
# 32768 on PCC) and none of those numbers exist as SDK constants — so none of
# them may appear as literals in the intelligence module. The boundary reads
# `SystemLanguageModel.default.contextSize` per request and derives every
# retrieval/history cap from it (ContextBudget.swift).
#
# Scope: MeetMemento/Services/Intelligence/ production sources only. Tests are
# the documented exception (they pin scaling behavior AT the known window
# sizes), and comment lines explaining the rule are stripped before matching.
#
# Usage: scripts/ci/check_no_hardcoded_context_budgets.sh
set -euo pipefail

MODULE_DIR="MeetMemento/Services/Intelligence"

if [ ! -d "$MODULE_DIR" ]; then
  echo "FAIL: $MODULE_DIR not found (run from the repo root)."
  exit 1
fi

# Strip line comments (// ...) then look for the forbidden window literals.
violations="$(
  find "$MODULE_DIR" -name '*.swift' -print0 \
    | xargs -0 grep -nH -E '.' 2>/dev/null \
    | sed 's|//.*$||' \
    | grep -E '\b(4096|8192|32768)\b' \
    || true
)"

if [ -n "$violations" ]; then
  echo "FAIL [spec 017 R9 / CONSTITUTION §4 rule 5]: hardcoded context-window"
  echo "literals found in the intelligence module. Read contextSize at runtime"
  echo "and derive budgets via ContextBudget instead:"
  echo ""
  echo "$violations"
  exit 1
fi

echo "OK [spec 017 R9]: no hardcoded context-window literals in $MODULE_DIR"
