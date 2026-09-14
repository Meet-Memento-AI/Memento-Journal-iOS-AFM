#!/usr/bin/env bash
#
# check_live_legal_urls.sh  (docs/app-store/00 A6, B1, B2)
#
# Confirms the published GitHub Pages legal site returns 200 and that the
# privacy policy describes the app that actually exists.
#
# 2026-09-12: this gate used to fail on ANY mention of "supabase". Spec 042
# deliberately added an opt-in verification disclosure naming Supabase, so the
# old rule failed a page that was correct — and a gate that cries wolf is a
# gate that gets ignored, which is exactly how the support-URL 404 survived to
# a rejection. The rule is now two-sided:
#
#   * FORBIDDEN — third-party AI backends the app does not use. Naming one is
#     the Guideline 5.1.1(i) / 5.1.2(i) inaccuracy we were rejected on.
#   * REQUIRED  — the spec 042 opt-in verification disclosure. Egress that is
#     real and undisclosed is the same defect pointing the other way, so the
#     page cannot silently regress to a "nothing ever leaves" version while
#     FeedbackSyncService ships.
set -euo pipefail

HOST="${LEGAL_HOST:-https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM}"
PRIVACY_TMP="$(mktemp -t memento-privacy)"
trap 'rm -f "$PRIVACY_TMP"' EXIT
fail=0

for page in index.html privacy.html terms.html support.html; do
  url="${HOST}/${page}"
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$url" || true)"
  if [ "$code" != "200" ]; then
    echo "FAIL: ${url} → HTTP ${code} (want 200)"
    fail=1
  else
    echo "OK   ${page} HTTP 200"
  fi
done

if ! curl -sS "${HOST}/privacy.html" -o "$PRIVACY_TMP"; then
  echo "FAIL: could not fetch ${HOST}/privacy.html for content checks"
  exit 1
fi

# --- Forbidden: backends the app does not use (docs/app-store/00 B2) ---------
forbidden=0
for name in openai gemini 'google ai' 'vertex ai' anthropic; do
  if grep -qi "$name" "$PRIVACY_TMP"; then
    echo "FAIL: privacy.html names '${name}', a backend this app does not use"
    forbidden=1
  fi
done
[ "$forbidden" -eq 0 ] && echo "OK   privacy.html names no third-party AI backend"
[ "$forbidden" -eq 0 ] || fail=1

# --- Required: the spec 042 opt-in verification disclosure -------------------
# Present only while the verification client ships. Mirrors the conditional in
# check_privacy_manifest.sh so the two gates cannot disagree.
CLIENT="MeetMemento/Services/Feedback/SupabaseFeedbackClient.swift"
if [ -f "$CLIENT" ]; then
  if grep -qi 'supabase' "$PRIVACY_TMP" && grep -qi 'quality feedback' "$PRIVACY_TMP"; then
    echo "OK   privacy.html discloses the opt-in verification pipeline (spec 042)"
  else
    echo "FAIL: ${CLIENT} ships, but privacy.html does not disclose the opt-in"
    echo "      quality-feedback pipeline. Real egress must be described."
    fail=1
  fi
else
  echo "SKIP ${CLIENT} absent — no verification disclosure required"
fi

# --- The live page must match the copy in this repo --------------------------
# A6's root cause was Pages serving a DIFFERENT repository, so the committed
# fix never reached production. Comparing bytes is what would have caught it.
if [ -f docs/privacy.html ]; then
  if diff -q docs/privacy.html "$PRIVACY_TMP" >/dev/null 2>&1; then
    echo "OK   live privacy.html matches docs/privacy.html"
  else
    echo "FAIL: live privacy.html differs from docs/privacy.html — Pages is"
    echo "      serving stale or foreign content (docs/app-store/00 A6)."
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: live legal URLs are not ready for App Store Connect."
  exit 1
fi
echo "OK: live legal URLs are ready."
