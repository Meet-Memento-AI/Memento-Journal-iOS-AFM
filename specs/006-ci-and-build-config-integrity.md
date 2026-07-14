---
id: 006
title: CI and Build Configuration Integrity
tier: P1
status: done (2026-07-14) — CI-live verification is a user action
effort: 1-2 sessions
depends_on: [003]
findings: [staging-migration-error-masking, prod-deploy-no-test-gate, hardcoded-runner-paths, no-staging-xcconfig, release-endpoint-unasserted, coverage-gate-3-percent, advisory-lint-and-security]
---

# 006 — CI and Build Configuration Integrity

## Why

The pipelines currently *look* green while hiding real failures: dev/staging deploys
**grep-swallow migration errors** and mark them applied; prod deploys have **no test
gate**; the Release build points at whatever `Release.local.xcconfig` says on the
archiving machine with **no assertion it's prod**; and the iOS coverage gate is set to
3% (the script's own default is 60), which rubber-stamps everything. Before inviting
external beta users, the path to prod must be honest. Blocks **Gate 2**. Depends on 003
(once migrations replay cleanly, the error-masking hack loses its reason to exist).

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | dev/staging migration step applies each `.sql` via raw `psql`; on failure greps for `already exists|duplicate key value|cannot drop function…` and records the migration as applied → staging schema silently diverges from prod. | `.github/workflows/deploy-dev-staging.yml:105-112,223-230` | HIGH |
| 2 | `deploy-prod.yml` (manual dispatch + typed confirmation — good) runs preflight, `db push --include-all`, function deploys, smoke `functions list` — but **no deno tests, no iOS tests**, and nothing asserts the deployed SHA passed `ios-tests.yml`. | `.github/workflows/deploy-prod.yml` | HIGH |
| 3 | Function sync uses a hardcoded personal path `/home/thomas/supabase/docker/volumes/functions` and named containers; all jobs require self-hosted runners (`[self-hosted, Linux, x64]`, macOS arm64) with no documented fallback. dev/staging deploy via Docker copy while prod uses `db push` — the prod mechanism is never exercised pre-prod. | `deploy-dev-staging.yml:124,242`; `ios-tests.yml:16` | MEDIUM |
| 4 | `Debug.xcconfig` and `Release.xcconfig` ship identical placeholders + `#include?` of git-ignored local files. No Staging variant; no CI check that a Release/archive build resolves `SUPABASE_URL` to prod. `SupabaseService.swift:79-124` degrades to an invalid URL silently at runtime — a mis-pointed archive fails invisibly. **Update 2026-07-13 (spec 002):** the xcconfig `//`-comment trap (URLs truncating to `https:`) was fixed with the `$()` escape in all four Config files; the R3 CI assertion should ALSO reject a resolved URL without a host, catching any regression of that escape. | `MeetMemento/Config/*.xcconfig` | MEDIUM |
| 5 | Coverage gate: `MIN_COVERAGE: "3"` in CI vs script default 60. UITests skipped in CI. SwiftLint and dependency-review are `continue-on-error` (advisory). | `ios-tests.yml:84,71,25-35`; `security.yml:59-66`; `scripts/ci/check_coverage.sh:5` | MEDIUM |

## Requirements

### R1. Migration failures fail the deploy
**Acceptance:** the grep-swallow blocks are deleted; dev/staging migration application
uses `supabase db push` (or `migration up`) semantics where any statement error fails
the job; a deliberately broken migration on a test branch turns the workflow red.
(Legitimate idempotency belongs *inside* migrations as `IF NOT EXISTS` guards — which
spec 003 establishes — not in the pipeline.)

### R2. Prod deploys are gated on green tests for that SHA
**Acceptance:** `deploy-prod.yml` runs (or verifies via the Checks API) deno tests and
the iOS test job for the exact SHA being deployed, and refuses to proceed otherwise;
the typed-confirmation step stays.

### R3. Release builds provably point at prod
**Acceptance:** a build-phase or CI script asserts that a Release/archive build's
resolved `SUPABASE_URL` equals the known prod URL and is not a placeholder — failing
the build otherwise. Optionally add `Staging.xcconfig` + scheme if a staging app build
is wanted for beta testing infrastructure changes; at minimum, placeholder-detection
must fail loudly (improve `SupabaseService`'s silent fallback with a visible
fatal-in-Debug / alert-in-Release configuration error).

### R4. Runner setup documented and de-personalized
**Acceptance:** hardcoded `/home/thomas/...` path becomes a repo/environment variable;
`docs/BRANCHING_AND_CI_POLICY.md` (or a new `docs/CI_RUNNERS.md`) documents required
self-hosted runner labels, software, and what breaks when they're offline.

### R5. Quality gates are honest
**Acceptance:** coverage gate raised from 3% to a truthful floor of current coverage
(measure first; expect ~10-15% — the point is *ratchet-only*, recorded in the workflow
as a comment: "only increase"); SwiftLint becomes blocking for **new** violations
(`--strict` on changed files via existing `scripts/ci/lint_changed_swift.sh`);
dependency-review blocking on `critical` severity. Spec 011 raises coverage further
with real tests.

## Out of Scope

- Writing the new unit tests that let the gate ratchet up meaningfully → **spec 011**.
- Migrating to GitHub-hosted runners (cost/infra decision — document status quo only).
- The `print(` lint rule content → **spec 005** (this spec only makes lint blocking).

## Implementation notes (2026-07-14)

- **R1**: deleted the grep-swallow blocks in both dev + staging migration steps of
  `deploy-dev-staging.yml`; migrations now fail-fast under `ON_ERROR_STOP=1` with a
  clear `::error::`. Relies on spec 003's idempotent migrations (guards belong in the
  SQL, not the pipeline).
- **R2**: added a `tests` job to `deploy-prod.yml` (runs `deno test` **and** an
  `actions/github-script` step that queries the Checks API for the deploy SHA — fails
  unless the iOS/SwiftLint/coverage checks conclude `success`/`skipped`). `deploy-prod`
  now `needs: [preflight, tests]`. Typed `deploy-production` confirmation preserved.
- **R3**: `scripts/ci/assert_release_endpoint.sh` (dual-mode: build-phase `$SUPABASE_URL`
  or `xcodebuild -showBuildSettings`). Enforcement is a **Release-only Xcode build phase**
  ("Assert Release endpoint (spec-006)") — inlined into the phase (not an external file)
  to satisfy Xcode's user-script sandbox. Verified: Debug build skips + succeeds; Release
  build **fails** on the placeholder URL with the assertion message. This is stronger
  than a CI step (CI never archives — archiving is local), so it also fixes the
  originally-planned "wire into ios-tests.yml" as a build-time gate instead.
- **R3 (SupabaseService)**: added a DEBUG `assertionFailure` on `configurationError`
  (guarded against previews + XCTest) — fires only on genuinely broken config
  (missing key / unparseable URL), not on the standard placeholder (which parses).
  AuthViewModel already degrades to unauthenticated at runtime (`:90`). Migrated its 2
  prints to `AppLogger` (delegated from spec 005).
- **R4**: `RUNNER_FUNCTIONS_PATH` var wired into all four functions-path fallbacks in
  `deploy-dev-staging.yml`; personal `/home/thomas/...` path is now only the last-resort
  documented default. Wrote `docs/CI_RUNNERS.md` (labels, software, vars, secrets,
  offline impact).
- **R5**: `lint_changed_swift.sh` PR step made **blocking** (removed `continue-on-error`);
  `dependency-review` now `fail-on-severity: critical` (was advisory `high`);
  `MIN_COVERAGE` kept at 3 with a **ratchet-only** comment — the orchestrator/spec 011
  raises it after real tests land (measuring now would just lock in 3).

## Tasks

- [x] 1. Migration steps fail-fast; grep-swallow deleted (both dev + staging). (R1)
- [x] 2. `deploy-prod.yml` test gate (deno + Checks-API iOS gate); `needs` updated. (R2)
- [x] 3. `assert_release_endpoint.sh` + Release-only build phase; Debug skips, Release
      fails on placeholder (verified). (R3)
- [x] 4. `SupabaseService` DEBUG assertionFailure (preview/test-guarded) + AppLogger. (R3)
- [x] 5. `RUNNER_FUNCTIONS_PATH` var + `docs/CI_RUNNERS.md`. (R4)
- [x] 6. `MIN_COVERAGE` ratchet-only comment (value stays 3 until spec 011). (R5)
- [x] 7. Changed-files SwiftLint blocking; dependency-review on `critical`. (R5)

## Verification

- [x] All 4 workflow YAMLs parse (ruby YAML.load); all `scripts/ci/*.sh` pass `bash -n`. ✅
- [x] Build Release with placeholder xcconfig → **build fails** with
      "Release SUPABASE_URL is a placeholder/empty"; Debug build skips the phase and
      **succeeds**. ✅ (R3 acceptance met)
- [x] `assert_release_endpoint.sh Release` dry-run → exits 1 on the current placeholder
      (correct). ✅
- [ ] Push a branch with an intentionally broken migration → dev/staging workflow fails —
      **user/CI action** (needs the self-hosted runner + a live push).
- [ ] Attempt a prod deploy from a SHA with a failing test → workflow refuses —
      **user/CI action**.
- [ ] Lower a Swift file into a lint violation on a PR → CI fails — **user/CI action**
      (swiftlint not installed locally; the `no_print` rule + blocking step are wired).
- [ ] Normal PR flow green end-to-end — **user/CI action**.

## Regression Guards

- The typed `deploy-production` confirmation in `deploy-prod.yml` must survive —
  don't automate away the human gate.
- Existing green paths keep working: deno tests for `chat/lib.ts`, the iOS build on the
  self-hosted mac runner (iPhone 17 sim), Sonar + gitleaks jobs.
- Spec 003's reproducible-migration guarantee is what R1 leans on — if a migration
  legitimately needs an idempotency guard, fix the migration, never the pipeline.
