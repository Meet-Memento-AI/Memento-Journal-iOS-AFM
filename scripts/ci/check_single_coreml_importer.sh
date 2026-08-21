#!/usr/bin/env bash
#
# check_single_coreml_importer.sh  (spec 031 / CONSTITUTION rule 11)
#
# Exactly one Swift module may `import CoreML`: the vendored SupertonicTTS
# package. The app target must stay CoreML-free.
#
set -euo pipefail

app_roots=()
for d in MeetMemento MeetMementoTests MeetMementoUITests; do
  [ -d "$d" ] && app_roots+=("$d")
done

app_importers=()
if [ "${#app_roots[@]}" -gt 0 ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    app_importers+=("$f")
  done < <(grep -rlE --include='*.swift' '^import[[:space:]]+CoreML' "${app_roots[@]}" 2>/dev/null | sort -u || true)
fi

echo "App-target CoreML importers found: ${#app_importers[@]}"
for f in "${app_importers[@]:-}"; do [ -n "$f" ] && echo "  - $f"; done

if [ "${#app_importers[@]}" -ne 0 ]; then
  echo "FAIL [spec 031]: MeetMemento app/tests import CoreML. Route through Packages/SupertonicTTS."
  exit 1
fi

pkg_importers=()
if [ -d Packages/SupertonicTTS ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    pkg_importers+=("$f")
  done < <(grep -rlE --include='*.swift' '^import[[:space:]]+CoreML' Packages/SupertonicTTS 2>/dev/null | sort -u || true)
fi

echo "Package CoreML importers found: ${#pkg_importers[@]}"
for f in "${pkg_importers[@]:-}"; do [ -n "$f" ] && echo "  - $f"; done

if [ "${#pkg_importers[@]}" -lt 1 ]; then
  echo "FAIL [spec 031]: expected CoreML import in Packages/SupertonicTTS."
  exit 1
fi

echo "OK [spec 031]: CoreML stays in the package; app target is CoreML-free."
