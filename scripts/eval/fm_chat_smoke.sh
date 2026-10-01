#!/usr/bin/env bash
# T5 — optional `fm` CLI smoke (macOS 27+). Does not gate merge by itself.
set -euo pipefail

if ! command -v fm >/dev/null 2>&1; then
  echo "SKIP: fm CLI not on PATH (install with Xcode 27 / macOS 27 SDK tooling)."
  exit 0
fi

PROMPT="${MEMENTO_FM_SMOKE_PROMPT:-Reply in one short sentence: what is a journal entry?}"
echo "fm smoke · category=fm_cli"
echo "$PROMPT" | fm chat --no-history 2>/dev/null | head -c 400 || {
  echo "WARN: fm chat failed or returned empty (Apple Intelligence may be off)."
  exit 0
}
echo
echo "OK   fm CLI responded"
