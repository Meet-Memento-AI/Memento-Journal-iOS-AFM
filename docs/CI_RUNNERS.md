# CI Runners

MeetMemento's GitHub Actions run on **self-hosted runners**. This document records
what they must provide so a runner can be rebuilt or replaced (spec-006).

## Runner labels

| Label set | Used by | Purpose |
|-----------|---------|---------|
| `[self-hosted, macOS, arm64]` (or the default macOS runner) | `ios-tests.yml` (ios-unit-ui) | Xcode build + unit/UI tests, coverage, SwiftLint, Periphery |
| `[self-hosted, Linux, x64]` | `ios-tests.yml` (deno-chat-lib), `security.yml`, `deploy-dev-staging.yml`, `deploy-prod.yml` | Deno tests, Sonar/gitleaks, Supabase deploys |

## Required software

**macOS runner:** Xcode (with the **iPhone 17 simulator** installed — workflows target
it by name), Homebrew, SwiftLint, Periphery, `xcbeautify` if used.

**Linux runner:** Docker (dev/staging Supabase stack runs in containers), the Supabase
CLI (prod deploy installs it per-run from the GitHub release tarball), Deno v2.x,
`sonar-scanner`, `gitleaks`, `psql`, `rsync`.

## Repository variables (Settings → Secrets and variables → Actions → Variables)

| Variable | Meaning | Default if unset |
|----------|---------|------------------|
| `RUNNER_FUNCTIONS_PATH` | Host path to the self-hosted Supabase edge-functions volume | `/home/thomas/supabase/docker/volumes/functions` (legacy personal path — set this var to de-couple from it) |
| `DEV_SUPABASE_FUNCTIONS_PATH` / `STAGING_SUPABASE_FUNCTIONS_PATH` | Per-env override of the functions path | falls back to `RUNNER_FUNCTIONS_PATH` |
| `DEV_SUPABASE_DB_CONTAINER` / `STAGING_SUPABASE_DB_CONTAINER` | Docker container name for the DB | `supabase-db` |
| `DEV_SUPABASE_EDGE_CONTAINER` / `STAGING_SUPABASE_EDGE_CONTAINER` | Docker container name for edge runtime | `supabase-edge-functions` |

## Required secrets

`PROD_SUPABASE_ACCESS_TOKEN`, `PROD_SUPABASE_PROJECT_REF` (prod deploy); dev/staging use
the containers directly on the runner.

## What breaks when a runner is offline

- **macOS runner down** → `ios-tests.yml` can't run → the **prod test gate**
  (`deploy-prod.yml` → `tests` job) fails its "iOS checks green for this SHA" assertion,
  so production deploys are blocked. This is intentional (spec-006 R2).
- **Linux runner down** → no Deno tests, no Sonar/gitleaks, no dev/staging/prod deploys.
- There is **no GitHub-hosted fallback** today (tracked in spec 012). If a runner is
  permanently lost, provision a replacement with the software above and re-register it
  with the matching labels.

## Local pre-archive check

Before archiving a Release build, the app target's **"Assert Release endpoint"** build
phase (spec-006 R3) fails the build if `SUPABASE_URL` is a placeholder or lacks a real
host. For a manual/CI check outside a build, run:

```
scripts/ci/assert_release_endpoint.sh Release
```
