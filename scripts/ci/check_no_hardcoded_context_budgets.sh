#!/usr/bin/env bash
#
# check_no_hardcoded_context_budgets.sh  (spec 017 / R9 — CONSTITUTION §4 rule 5)
#
# Rule 5's corollary: "no hardcoded model context budgets — the window is
# 4096/8192/32768 depending on device and zone; read contextSize at runtime and
# size retrieved-entry payloads against it."
#
# Spec 017 R9 states the acceptance as a grep for those three numbers over the
# intelligence module. That check is necessary but NOT sufficient, and on its own
# it is worthless here: it already passed before any of this work existed,
# because the module hardcoded *derived* values (7 entries, 500 chars) rather
# than window sizes. A gate that is green on a codebase with no budgeting at all
# proves nothing. It would also wave through `4 << 10`, which is 4096 spelled to
# evade a grep.
#
# So this gate asserts three things:
#
#   1. No window literals, and no obvious obfuscations of them.
#   2. Every integer literal handed to .prefix()/.suffix() in the module carries
#      a `budget-exempt:` marker explaining why it is not a context budget. This
#      is what actually enforces "derived, not assumed" — the numbers that matter
#      are payload caps, not the window.
#   3. A real `contextSize` read exists. Without this, deleting ContextBudget
#      would leave rules 1 and 2 trivially satisfied.
#
# Comments and test files are exempt throughout — spec 017 R9 says so explicitly,
# and a test is exactly where a concrete window belongs.
#
# Usage: scripts/ci/check_no_hardcoded_context_budgets.sh
set -euo pipefail

MODULE="${INTELLIGENCE_MODULE_DIR:-MeetMemento/Services/Intelligence}"

if [ ! -d "$MODULE" ]; then
  echo "FAIL: intelligence module not found at $MODULE"
  exit 1
fi

status=0

# Strip // comments and blank lines so prose about the rule doesn't trip it.
# (Block comments are not used for these headers in this module.)
strip_comments() { sed -e 's://.*::' "$1"; }

# ---- 1. Window literals and obfuscations ---------------------------------
echo "== Checking for hardcoded window literals =="
window_hits=""
for f in "$MODULE"/*.swift; do
  hits=$(strip_comments "$f" \
    | grep -nE '(\b(4096|8192|32768)\b|[0-9]+[[:space:]]*<<[[:space:]]*1[0-9]|\b[0-9]+[[:space:]]*\*[[:space:]]*1024\b)' \
    || true)
  if [ -n "$hits" ]; then
    window_hits="${window_hits}${f}:\n${hits}\n"
  fi
done

if [ -n "$window_hits" ]; then
  echo ""
  echo "FAIL [REQ-INT-009 / spec 017 R9]: a context-window size is hardcoded in the"
  echo "intelligence module. The window is a runtime value — read contextSize and"
  echo "derive from it. If the SDK cannot report a window, model that as a state"
  echo "(ContextWindow.unavailable); do not substitute a literal, and do not spell"
  echo "one as a shift or a multiplication."
  printf "%b" "$window_hits"
  status=1
else
  echo "OK: no window literals or obfuscations."
fi

# ---- 2. Payload caps must be derived or explicitly exempt ----------------
echo ""
echo "== Checking prefix/suffix literals carry a budget-exempt rationale =="
cap_hits=""
for f in "$MODULE"/*.swift; do
  # A numeric literal passed directly to prefix()/suffix(), on a line that does
  # not declare why it is exempt.
  hits=$(strip_comments "$f" \
    | grep -nE '\.(prefix|suffix)\([0-9]+\)' \
    || true)
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    lineno="${hit%%:*}"
    # Re-read the ORIGINAL text (comments intact) to look for the marker. The
    # marker may sit on the line itself or in the comment directly above it —
    # the rationale is often too long to fit inline without breaking the
    # line-length lint.
    prev=$(( lineno > 1 ? lineno - 1 : 1 ))
    context=$(sed -n "${prev},${lineno}p" "$f")
    case "$context" in
      *budget-exempt:*) ;;
      *) cap_hits="${cap_hits}${f}:${hit}\n" ;;
    esac
  done <<< "$hits"
done

if [ -n "$cap_hits" ]; then
  echo ""
  echo "FAIL [spec 017 R9]: a payload cap is a compile-time literal. Derive it from"
  echo "ContextBudget, or, if it genuinely is not a context budget (a dedup"
  echo "fingerprint, an embedding input cap), annotate the line:"
  echo "    .prefix(200)  // budget-exempt: dedup fingerprint, not a model payload"
  printf "%b" "$cap_hits"
  status=1
else
  echo "OK: every prefix/suffix literal is derived or explicitly exempt."
fi

# ---- 3. The window is actually read --------------------------------------
echo ""
echo "== Checking the runtime window is actually read =="
if grep -rqE '\bcontextSize\b' --include='*.swift' "$MODULE"; then
  echo "OK: contextSize is read at runtime."
else
  echo ""
  echo "FAIL [CONSTITUTION §4 rule 5]: nothing in the intelligence module reads"
  echo "contextSize. Rules 1 and 2 above are trivially satisfied by a module that"
  echo "does no budgeting at all — this is the check that makes them mean something."
  status=1
fi

echo ""
if [ "$status" -eq 0 ]; then
  echo "OK [REQ-INT-009 / spec 017 R9 / CONSTITUTION §4 rule 5]"
fi
exit "$status"
