#!/usr/bin/env bash
#
# check_live_legal_urls.sh  (docs/app-store/00 A6, B1, B2)
#
# Confirms the published GitHub Pages legal site returns 200 and that the
# privacy policy does not name third-party AI backends the app no longer uses.
set -euo pipefail

HOST="${LEGAL_HOST:-https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM}"
fail=0

for page in index.html privacy.html terms.html support.html; do
  url="${HOST}/${page}"
  code="$(curl -sS -o /tmp/memento-legal-page.html -w '%{http_code}' "$url" || true)"
  if [ "$code" != "200" ]; then
    echo "FAIL: ${url} → HTTP ${code} (want 200)"
    fail=1
  else
    echo "OK   ${page} HTTP 200"
  fi
done

if curl -sS "${HOST}/privacy.html" | grep -qiE 'openai|supabase|gemini'; then
  echo "FAIL: privacy.html still names OpenAI, Supabase, or Gemini"
  fail=1
else
  echo "OK   privacy.html has no OpenAI/Supabase/Gemini"
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: live legal URLs are not ready for App Store Connect."
  exit 1
fi
echo "OK: live legal URLs are ready."
