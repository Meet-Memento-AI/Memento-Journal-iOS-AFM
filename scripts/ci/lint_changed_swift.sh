#!/usr/bin/env bash
set -euo pipefail

BASE_REF="${1:-${GITHUB_BASE_REF:-dev}}"

if [[ -z "$BASE_REF" ]]; then
  echo "No base ref provided; running full lint as fallback."
  swiftlint lint --strict
  exit 0
fi

echo "Linting changed Swift files relative to origin/$BASE_REF"
git fetch origin "$BASE_REF" --depth=1

if git merge-base "origin/$BASE_REF" HEAD >/dev/null 2>&1; then
  DIFF_RANGE="origin/$BASE_REF...HEAD"
else
  DIFF_RANGE="origin/$BASE_REF..HEAD"
fi

changed=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  changed+=("$line")
done < <(git diff --name-only "$DIFF_RANGE" -- '*.swift' || true)

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "No changed Swift files detected; skipping SwiftLint."
  exit 0
fi

swift_files=()
for path in "${changed[@]}"; do
  if [[ -f "$path" ]]; then
    swift_files+=("$path")
  fi
done

if [[ ${#swift_files[@]} -eq 0 ]]; then
  echo "No existing changed Swift files to lint."
  exit 0
fi

for i in "${!swift_files[@]}"; do
  export "SCRIPT_INPUT_FILE_$i=${swift_files[$i]}"
done
export SCRIPT_INPUT_FILE_COUNT="${#swift_files[@]}"

printf 'SwiftLint targets:\n'
printf ' - %s\n' "${swift_files[@]}"

swiftlint lint --strict --use-script-input-files
