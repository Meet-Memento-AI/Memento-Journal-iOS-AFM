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

# `--use-script-input-files` does not honor `.swiftlint.yml` included/excluded.
# Keep this filter in sync with that file: only the app target is linted, and
# pre-existing oversized types are skipped (Phase II touches them only to
# carry facts / skip the model / speak Swift n).
swift_files=()
for path in "${changed[@]}"; do
  [[ -f "$path" ]] || continue
  [[ "$path" == withMemento/* ]] || continue
  case "$path" in
    withMemento/Services/Intelligence/FoundationModelsIntelligenceService.swift|\
    withMemento/ViewModels/ChatViewModel.swift|\
    withMemento/Services/ChatService.swift|\
    withMemento/Components/AIChat/ChatMessagesView.swift)
      echo "Skipping excluded $path"
      continue
      ;;
  esac
  swift_files+=("$path")
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

# Report only violations on lines this change adds or modifies. Linting whole
# files made "no new violations" mean "no violations anywhere in any file you
# touched", so a mechanical edit (the withMemento rename touched ~330 files)
# resurfaced ~390 pre-existing violations and blocked the merge on work nobody
# did. File-scoped rules (file_length, type_body_length, ...) report on the
# declaration line and count only if that line changed.
added_lines="$(mktemp "${TMPDIR:-/tmp}/lint-added.XXXXXX")"
lint_out="$(mktemp "${TMPDIR:-/tmp}/lint-out.XXXXXX")"
trap 'rm -f "$added_lines" "$lint_out"' EXIT

git diff --unified=0 --no-color "$DIFF_RANGE" -- "${swift_files[@]}" | awk '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^@@/ {
    split($3, a, ",")
    start = substr(a[1], 2) + 0
    count = (a[2] == "" ? 1 : a[2] + 0)
    for (i = 0; i < count; i++) print file ":" (start + i)
  }
' > "$added_lines"

swiftlint lint --strict --quiet --use-script-input-files > "$lint_out" || true

new_violations="$(python3 scripts/ci/filter_lint_to_lines.py "$added_lines" "$lint_out" "$PWD")"

total="$(grep -cE ': (error|warning): ' "$lint_out" || true)"
if [[ -n "$new_violations" ]]; then
  echo "$new_violations"
  echo ""
  echo "FAIL: $(printf '%s\n' "$new_violations" | wc -l | tr -d ' ') SwiftLint violation(s) on lines changed relative to origin/$BASE_REF."
  echo "(${total} total in the touched files; only the changed lines block.)"
  exit 2
fi
echo "OK: no SwiftLint violations on changed lines (${total} pre-existing in touched files, not blocking)."
