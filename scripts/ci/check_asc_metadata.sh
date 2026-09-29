#!/usr/bin/env bash
#
# check_asc_metadata.sh  (docs/app-store/04, /08)
#
# Holds the App Store Connect copy to the same standard as the app's own strings:
#
#   1. Character/byte limits per field. Apple truncates or refuses silently in
#      the UI; catching it here means the drafts in the repo are always pasteable.
#   2. REQ-POS-001 - no absolute-privacy claim the PCC routing contradicts.
#      Delegates to scripts/ci/lint_forbidden_phrases.py, the same linter that
#      guards in-app string literals (spec 014 R3).
#   3. No pricing in metadata (Guideline 2.3.7).
#   4. No clinical vocabulary (Guidelines 1.4.1 / 5.1.1(ix)) - Memento is
#      enrolled as an INDIVIDUAL developer, and health positioning moves it into
#      "should be submitted by a legal entity" territory. See docs/app-store/01.
#
# Usage: scripts/ci/check_asc_metadata.sh
set -euo pipefail

META_DIR="${META_DIR:-docs/app-store/metadata/en-US}"
LINTER="${LINTER:-scripts/ci/lint_forbidden_phrases.py}"

[ -d "$META_DIR" ] || { echo "FAIL: metadata dir not found: $META_DIR"; exit 1; }

fail=0
note() { echo "  $*"; }

# field|limit|unit   (counts exclude the trailing newline)
LIMITS=(
  "name|30|chars"
  "subtitle|30|chars"
  "keywords|100|chars"
  "promotional_text|170|chars"
  "description|4000|chars"
  "release_notes|4000|chars"
  "review_notes|4000|bytes"
  # Resolution Center reply. Apple caps it at 4000 CHARACTERS, a separate
  # limit from the Notes field's 4000 bytes, so it is measured separately
  # and the two files are allowed to differ. They must not CONTRADICT each
  # other - see docs/app-store/08 section 5 rule 6.
  "resolution_center_reply|4000|chars"
)

echo "App Store Connect metadata: $META_DIR"
echo ""

for entry in "${LIMITS[@]}"; do
  IFS='|' read -r field limit unit <<< "$entry"
  f="$META_DIR/$field.txt"
  if [ ! -f "$f" ]; then
    echo "FAIL: missing $f"
    fail=1
    continue
  fi

  if [ "$unit" = "bytes" ]; then
    n=$(( $(wc -c < "$f") - 1 ))
  else
    n=$(( $(wc -m < "$f") - 1 ))
  fi

  if [ "$n" -gt "$limit" ]; then
    echo "FAIL $field.txt: $n $unit (limit $limit)"
    fail=1
  else
    printf "OK   %-20s %5d / %s %s\n" "$field.txt" "$n" "$limit" "$unit"
  fi
done

# --- keywords: comma-separated, no space after commas ------------------------
if grep -q ', ' "$META_DIR/keywords.txt" 2>/dev/null; then
  echo "FAIL keywords.txt: contains ', ' - a space after a comma wastes a"
  note "character. Spaces are allowed only WITHIN a multi-word phrase."
  fail=1
fi

echo ""

# --- REQ-POS-001 --------------------------------------------------------------
if [ -x "$LINTER" ] || [ -f "$LINTER" ]; then
  python3 "$LINTER" "$(dirname "$META_DIR")" || fail=1
else
  echo "FAIL: linter not found: $LINTER"
  fail=1
fi

echo ""

# --- No pricing in metadata (Guideline 2.3.7) --------------------------------
# The description may name the subscription, but never a price.
#
# `--include='*.txt'` because this directory stopped being text-only on
# 2026-09-24, when the App Store screenshots landed in it (D9). A recursive grep
# over PNG bytes matches these patterns by chance and reports "pricing found in
# metadata" for all eight frames. The check is about store *copy*; the frames
# are checked by `export_screenshots.sh` instead, on dimensions and
# distinctness.
if grep -rnE --include='*.txt' \
     '\$[0-9]|[0-9]+\.[0-9]{2} ?(USD|EUR|GBP)|[0-9]+ ?% (accurate|accuracy)' \
     "$META_DIR" 2>/dev/null; then
  echo "FAIL: pricing or an accuracy claim found in metadata."
  note "Guideline 2.3.7 forbids pricing in metadata - the store shows it."
  note "Accuracy percentages are unverifiable claims. See docs/app-store/04."
  fail=1
else
  echo "OK   no pricing, no accuracy claims"
fi

# --- No clinical vocabulary (Guidelines 1.4.1 / 5.1.1(ix)) -------------------
# Matched per PARAGRAPH, not per line: the copy is hard-wrapped, so the
# disclaimers that legitimately use this vocabulary ("The app does not give
# advice... or offer treatment information") straddle line breaks. Those
# sentences are the defense against 5.1.1(ix), not the violation - so a
# paragraph containing an explicit negation is allowed, and one asserting
# clinical benefit is not.
CLINICAL='therapy|therapist|therapeutic|mental health|anxiety|depression|diagnos|treatment|clinical|psychiatr|self-care'
NEGATED='not a (health|wellness)|does not (give|make|diagnos|offer)|is not a substitute|never (generated|model-generated)'
hits=""
for f in "$META_DIR"/*.txt; do
  para="$(awk -v RS='' -v f="$f" '{gsub(/\n/, " "); print f ": " $0}' "$f")"
  while IFS= read -r block; do
    [ -z "$block" ] && continue
    printf '%s' "$block" | grep -qiE "$CLINICAL" || continue
    printf '%s' "$block" | grep -qiE "$NEGATED" && continue
    hits="$hits$block"$'\n'
  done <<< "$para"
done
if [ -n "$hits" ]; then
  echo "FAIL: clinical vocabulary in App Store metadata:"
  printf '%s\n' "$hits" | sed 's/^/  /'
  note ""
  note "Memento is enrolled as an INDIVIDUAL developer. Guideline 5.1.1(ix) says"
  note "healthcare apps 'should be submitted by a legal entity... and not by an"
  note "individual developer'. Health framing also pushes the age rating from 9+"
  note "to 13+/16+. See docs/app-store/01 section 1.4.1 and docs/app-store/05."
  fail=1
else
  echo "OK   no clinical vocabulary"
fi

# --- Regional-difference claim matches the shipped crisis resources ----------
# review_notes.txt section 5 tells App Review the crisis card is IDENTICAL in
# every region. That is true today only because CrisisResources.json ships a
# single locale block, so every locale falls through to defaultLocale. Add a
# second block and the statement to Apple silently becomes false - a Guideline
# 2.3 accuracy defect in the one answer Apple explicitly asked for (item 5 of
# the September 2026 information request). See docs/app-store/08 section 2.
CRISIS_JSON="${CRISIS_JSON:-withMemento/Resources/Safety/CrisisResources.json}"
NOTES_FILE="$META_DIR/review_notes.txt"
if [ -f "$CRISIS_JSON" ] && [ -f "$NOTES_FILE" ]; then
  if grep -qi "identical in every region" "$NOTES_FILE"; then
    locale_count="$(python3 -c "
import json,sys
print(len(json.load(open(sys.argv[1]))['locales']))
" "$CRISIS_JSON")"
    if [ "$locale_count" -eq 1 ]; then
      echo "OK   crisis resources ship 1 locale; the region-identical claim holds"
    else
      echo "FAIL: review_notes.txt tells App Review the crisis card is identical"
      echo "      in every region, but $CRISIS_JSON now ships $locale_count locales."
      note "Either revert to a single locale, or rewrite review_notes.txt section 5"
      note "to describe the regional variation. Do not ship the claim and the"
      note "variation together. See docs/app-store/08 section 2."
      fail=1
    fi
  fi
fi

echo ""
if [ "$fail" -ne 0 ]; then
  echo "FAIL [docs/app-store/04, /08]: App Store metadata checks did not pass."
  exit 1
fi
echo "OK [docs/app-store/04, /08]: App Store metadata checks passed."
