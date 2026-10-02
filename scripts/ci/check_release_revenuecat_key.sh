#!/usr/bin/env bash
#
# check_release_revenuecat_key.sh  (spec 021 R3)
#
# Refuses a distribution build whose RevenueCat key is missing or is a Test
# Store key.
#
# Why this exists: `withMemento/Config/Release.xcconfig` supplies
# REVENUECAT_API_KEY from the gitignored RevenueCat.release.xcconfig. If that
# file is absent the key resolves empty, `EntitlementStore.isConfigured` stays
# false, and `ProAccess.decide` **fails open** — every paid surface unlocks.
# The build succeeds, every test passes, and the app ships giving Pro away
# while App Store Connect sells a subscription against it. Nothing in the
# project catches that today, which is how it survived to build 4.
#
# Deliberately NOT a build phase and NOT part of `iOS build (online)`: that
# lane archives Release for the size gate and has no production key, so a hard
# failure there would block every PR. This runs in the release train instead,
# between `xcodebuild archive` and `altool --validate-app`.
#
# Usage:
#   scripts/ci/check_release_revenuecat_key.sh <path/to/withMemento.app>
#   scripts/ci/check_release_revenuecat_key.sh <path/to/Foo.xcarchive>
set -euo pipefail

target="${1:-}"
if [ -z "$target" ]; then
  echo "usage: $0 <withMemento.app | *.xcarchive>" >&2
  exit 2
fi

# Accept an archive and find the app inside it.
if [[ "$target" == *.xcarchive ]]; then
  app="$(find "$target/Products/Applications" -maxdepth 1 -name '*.app' | head -1 || true)"
else
  app="$target"
fi

if [ -z "${app:-}" ] || [ ! -d "$app" ]; then
  echo "FAIL: no .app found at $target" >&2
  exit 1
fi

plist="$app/Info.plist"
[ -f "$plist" ] || { echo "FAIL: no Info.plist in $app" >&2; exit 1; }

key="$(/usr/libexec/PlistBuddy -c 'Print :REVENUECAT_API_KEY' "$plist" 2>/dev/null || true)"

echo "Bundle:  $app"

if [ -z "$key" ] || [[ "$key" == '$('* ]]; then
  cat >&2 <<'MSG'
FAIL [spec 021 R3]: REVENUECAT_API_KEY is empty or unexpanded in the built bundle.

  EntitlementStore will not configure, ProAccess fails open, and every paid
  surface unlocks. This build would give Memento Pro away for free.

  Fix: create withMemento/Config/RevenueCat.release.xcconfig (gitignored) with
       REVENUECAT_API_KEY = appl_xxxxxxxxxxxxxxxxxxxx
  then re-archive.
MSG
  exit 1
fi

if [[ "$key" == test_* ]]; then
  cat >&2 <<'MSG'
FAIL [spec 021 R3]: this bundle carries a RevenueCat **Test Store** key.

  A `test_` key is for the simulator and the Test Store. RevenueCat rejects it
  in a distribution build, so purchases would fail for every real customer.

  Fix: put the production `appl_` key in RevenueCat.release.xcconfig.
MSG
  exit 1
fi

if [[ "$key" != appl_* ]]; then
  echo "FAIL [spec 021 R3]: REVENUECAT_API_KEY does not look like an Apple platform key (expected appl_…)." >&2
  exit 1
fi

# Never print the key itself.
echo "OK [spec 021 R3]: production RevenueCat key present (appl_…, ${#key} chars)."
