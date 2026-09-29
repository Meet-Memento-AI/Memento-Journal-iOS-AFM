#!/usr/bin/env bash
#
# check_theme_color_bypass.sh  (docs/app-store/12 A2.2 / MEM-278)
#
# Raw colours outside Theme.swift are how light surfaces leak into dark mode.
# Route through `theme.*` or a palette in Theme.swift instead. Shadow colours
# are exempt; anything else that is genuinely scheme-independent (mask alpha,
# colours sampled from a photo, overlays on fixed-dark media) carries a
# trailing `// theme-exempt: <reason>`.
#
set -euo pipefail

pattern='Color\.(white|black)\b|Color\((hex|red):|(foregroundStyle|foregroundColor|fill|background|tint|stroke)\([[:space:]]*\.(white|black)\b'

hits=$(grep -rnE --include='*.swift' "$pattern" withMemento withMementoWatch 2>/dev/null \
  | grep -v '^withMemento/Resources/Theme.swift:' \
  | grep -vE 'shadow|theme-exempt:' || true)

if [ -n "$hits" ]; then
  echo "FAIL [A2.2]: raw colours outside Theme.swift (use a theme token, or add '// theme-exempt: <reason>'):"
  echo "$hits"
  exit 1
fi
echo "OK [A2.2]: no raw colours outside Theme.swift."
