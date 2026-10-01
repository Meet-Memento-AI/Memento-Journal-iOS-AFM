#!/usr/bin/env bash
# Ask chat 100/100 · T6 — decide whether the blocking device gate must run.
#
# Matches the plan gate table: prompt version strings, ReplyRenderer.version,
# PromptExperiments defaults, ReplyChannel caps/temperature, safety packs.
#
# Usage:
#   scripts/ci/detect_behavioural_change.sh [<base_ref>]
#
# With GITHUB_OUTPUT set (Actions), writes:
#   required=true|false
#   reason=<short text>
#
# Override for drills: BEHAVIOURAL_GATE_FORCE=1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "${BEHAVIOURAL_GATE_FORCE:-}" == "1" ]]; then
  reason="BEHAVIOURAL_GATE_FORCE=1"
  required=true
else
  base="${1:-}"
  if [[ -z "$base" ]]; then
    if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
      base="$(python3 - <<'PY' "$GITHUB_EVENT_PATH"
import json, sys
ev = json.load(open(sys.argv[1]))
pr = ev.get("pull_request") or {}
print(pr.get("base", {}).get("sha", ""))
PY
)"
    fi
  fi
  if [[ -z "$base" ]]; then
    base="$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse HEAD~1)"
  fi

  mapfile -t changed < <(git diff --name-only "$base"...HEAD 2>/dev/null || git diff --name-only "$base" HEAD)

  required=false
  reason="no behavioural paths in diff"

  path_patterns=(
    'withMemento/Services/Intelligence/Prompt/PromptRegistry.swift'
    'withMemento/Services/Intelligence/Reconciliation/ReplyRenderer'
    'withMemento/Services/Intelligence/Routing/ReplyChannel.swift'
    'withMemento/Services/Intelligence/Safety/'
    'withMemento/Resources/Safety/'
  )

  for file in "${changed[@]}"; do
    for pat in "${path_patterns[@]}"; do
      if [[ "$file" == "$pat" || "$file" == "$pat"* ]]; then
        required=true
        reason="path:$file"
        break 2
      fi
    done
  done

  if [[ "$required" == "false" ]]; then
    # Version / experiment bumps anywhere under Intelligence/
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      if git diff "$base"...HEAD -- "$file" | grep -Eq \
        'reply-render@[0-9]+|ask-core@[0-9]+|ask-degraded@[0-9]+|chat-companion@[0-9]+|chat-light@[0-9]+|static let version|PromptExperiments\.|maximumResponseTokens|var temperature'; then
        required=true
        reason="content:$file"
        break
      fi
    done < <(printf '%s\n' "${changed[@]}" | grep -E '^withMemento/Services/Intelligence/' || true)
  fi
fi

echo "behavioural_device_gate_required=$required"
echo "behavioural_device_gate_reason=$reason"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "required=$required"
    echo "reason=$reason"
  } >>"$GITHUB_OUTPUT"
fi

if [[ "$required" == "true" ]]; then
  exit 0
fi
exit 0
