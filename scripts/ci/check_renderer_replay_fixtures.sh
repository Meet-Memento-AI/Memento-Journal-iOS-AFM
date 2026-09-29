#!/usr/bin/env bash
# T2 (MEM-324): Study VI replay fixtures stay in sync with eval-archive.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 scripts/eval/regen_renderer_replay_fixtures.py --check
