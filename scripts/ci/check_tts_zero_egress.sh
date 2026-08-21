#!/usr/bin/env bash
#
# check_tts_zero_egress.sh  (spec 030 / 036)
#
# TTS path must never fetch weights. Fail if huggingface.co (or similar)
# appears in the neural TTS Swift sources or vendored package.
#
set -euo pipefail

roots=(MeetMemento/Services/Voice Packages/SupertonicTTS)
existing=()
for d in "${roots[@]}"; do
  [ -d "$d" ] && existing+=("$d")
done

hits=()
if [ "${#existing[@]}" -gt 0 ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    hits+=("$f")
  done < <(grep -rlE --include='*.swift' 'huggingface\.co|hf\.co/|download.*mlmodel' "${existing[@]}" 2>/dev/null | sort -u || true)
fi

echo "TTS egress hits: ${#hits[@]}"
for f in "${hits[@]:-}"; do [ -n "$f" ] && echo "  - $f"; done

if [ "${#hits[@]}" -ne 0 ]; then
  echo "FAIL [spec 030/036]: neural TTS path references a network weight host."
  exit 1
fi

echo "OK [spec 030/036]: no huggingface.co (or weight-download) in the TTS path."
