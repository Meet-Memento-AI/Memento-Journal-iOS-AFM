#!/usr/bin/env bash
#
# check_tts_license_path.sh  (spec 018 R12 / REQ-TTS-009)
#
# R12's acceptance reads: "Given the shipped dependency tree, when it is
# scanned in CI, then no GPL-family license text and no espeak/phonemizer
# component appears in any TTS path." That gate did not exist until now; the
# property held only by construction.
#
# Why this is a real trap and not a hypothetical: espeak-ng is GPL-3 and sits
# inside the grapheme-to-phoneme path of Kokoro, sherpa-onnx, and Piper alike.
# The contamination is invisible from the top of the dependency tree — it lives
# two levels down, inside a component nobody classifies as "the model," in an
# app that is otherwise closed-source. Supertonic qualifies by being G2P-free;
# this gate is what keeps it that way when someone swaps the engine.
#
# Scope: the TTS path only (Services/Voice + the vendored package). GPL
# elsewhere is a different question this gate deliberately does not answer.
set -euo pipefail

roots=(MeetMemento/Services/Voice Packages MeetMemento/Resources/Voices)
existing=()
for d in "${roots[@]}"; do
  [ -d "$d" ] && existing+=("$d")
done

if [ "${#existing[@]}" -eq 0 ]; then
  echo "OK [spec 018 R12]: no TTS path present to scan."
  exit 0
fi

fail=0

# --- 1. GPL-family license text ----------------------------------------------
# Matches the distinctive phrasings, not the bare token "GPL", so a comment
# saying "must not be GPL" does not trip the gate it documents.
gpl_pattern='GNU General Public License|GNU Lesser General Public|GNU Affero|gpl-3\.0|gpl-2\.0|lgpl-|agpl-|COPYING\.GPL'
gpl_hits=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  gpl_hits+=("$f")
done < <(grep -rlE "$gpl_pattern" "${existing[@]}" 2>/dev/null | sort -u || true)

echo "GPL-family license hits: ${#gpl_hits[@]}"
for f in "${gpl_hits[@]:-}"; do [ -n "$f" ] && echo "  - $f"; done
if [ "${#gpl_hits[@]}" -ne 0 ]; then
  echo "FAIL [spec 018 R12 / REQ-TTS-009]: GPL-family license text in the TTS path."
  echo "      A closed-source app cannot ship it. Replace the component."
  fail=1
fi

# --- 2. espeak / phonemizer G2P components -----------------------------------
# Two traps this pattern has to dodge, both hit on the first run of this gate:
#
#   1. `pauseSpeaking` / `continueSpeaking` contain the substring "eSpeak".
#      A bare case-insensitive `espeak` matches every AVSpeechSynthesizer call
#      site. Hence the leading word boundary.
#   2. The files that document the ABSENCE of a phonemizer ("No phonemizer, no
#      IPA, no espeak") are the ones most likely to name it. Failing on your own
#      documentation is the cry-wolf failure this repo already paid for once, so
#      comments are stripped before matching — a real dependency shows up in
#      code, imports, or a filename, never only in prose.
g2p_pattern='\b(espeak|e-speak|libespeak|gruut|deepphonemizer|phonemiz)'
g2p_hits=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # Strip // line comments, then match. A file whose only mention is a comment
  # is documentation, not a dependency.
  if sed -E 's@//.*$@@' "$f" | grep -qEi "$g2p_pattern"; then
    g2p_hits+=("$f")
  fi
done < <(find "${existing[@]}" -type f \( -name '*.swift' -o -name 'Package.swift' -o -name '*.json' \) 2>/dev/null | sort -u || true)

# A component can also arrive as a file or directory name.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  g2p_hits+=("$f (filename)")
done < <(find "${existing[@]}" \( -iname '*espeak*' -o -iname '*phonemiz*' -o -iname '*gruut*' \) 2>/dev/null | sort -u || true)

echo "G2P / phonemizer hits: ${#g2p_hits[@]}"
for f in "${g2p_hits[@]:-}"; do [ -n "$f" ] && echo "  - $f"; done
if [ "${#g2p_hits[@]}" -ne 0 ]; then
  echo "FAIL [spec 018 R12 / REQ-TTS-009]: a phonemizer/G2P component appears in"
  echo "      the TTS path. R12 admits an engine only if it is G2P-free or has a"
  echo "      demonstrably permissive front end, recorded in its spec first."
  fail=1
fi

# --- 3. The weight attribution must ship in the app --------------------------
# DEC-010 / R6: where a weight license carries an attribution condition, the
# attribution is a license term, not a courtesy. Assert the surface exists.
ACK="MeetMemento/Views/Settings/AcknowledgmentsView.swift"
if [ -d MeetMemento/Resources/Voices ]; then
  if [ ! -f "$ACK" ]; then
    echo "FAIL [spec 030 R6 / DEC-010]: voice weights ship but $ACK is missing."
    fail=1
  elif ! grep -qi 'openrail' "$ACK"; then
    echo "FAIL [spec 030 R6 / DEC-010]: $ACK does not name the weights' licence."
    fail=1
  else
    echo "OK   weight attribution surface present and names the licence"
  fi
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "OK [spec 018 R12 / REQ-TTS-009]: TTS path is GPL-free and G2P-free."
