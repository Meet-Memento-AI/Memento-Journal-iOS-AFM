#!/usr/bin/env bash
#
# check_no_sirikit.sh  (spec 020 R1 / REQ-SYS-004)
#
set -euo pipefail

hits=$(grep -rlE --include='*.swift' '^import[[:space:]]+Intents|INIntent|INExtension' MeetMemento 2>/dev/null | sort -u || true)
if [ -n "$hits" ]; then
  echo "FAIL [spec 020]: SiriKit types present:"
  echo "$hits"
  exit 1
fi
echo "OK [spec 020]: no SiriKit importer."
