#!/usr/bin/env bash
#
# check_content_free_logs.sh  (Ask 100/100 PS6 — CONSTITUTION §4 rule 3)
#
# AppLogger and PerfSignposts logger calls under Services/Intelligence must not
# interpolate journal text, questions, prompts, or error messages that may echo
# user content. Counters, enum codes, and stable identifiers only.
#
# Usage: scripts/ci/check_content_free_logs.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
exec python3 scripts/ci/check_content_free_logs.py "$@"
