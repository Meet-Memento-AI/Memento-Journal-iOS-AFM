---
id: 006
title: CI and Build Configuration Integrity
tier: P1
status: not-started
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
| 4 | `Debug.xcconfig` and `Release.xcconfig` ship identical placeholders + `#include?` of git-ignored local files. No Staging variant; no CI check that a Release/archive build resolves `SUPABASE_URL` to prod. `SupabaseService.swift:79-124` degrades to an invalid URL silently at runtime — a mis-pointed archive fails invisibly. | `MeetMemento/Config/*.xcconfig` | MEDIUM |
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

## Tasks

- [ ] 1. Delete the grep-swallow blocks; switch dev/staging migration application to
      fail-fast (`supabase db push` against the target, or psql with `ON_ERROR_STOP=1`
      and no error filtering). Requires 003 done. (R1)
- [ ] 2. Test-gate prod: add deno-test + iOS-test verification (job dependency or
      Checks-API query for the SHA) to `deploy-prod.yml`. (R2)
- [ ] 3. Add the Release endpoint assertion script (`scripts/ci/assert_release_endpoint.sh`):
      resolve build settings via `xcodebuild -showBuildSettings -configuration Release`,
      fail on placeholder or non-prod URL; call it in `ios-tests.yml` and document it
      for local archiving. (R3)
- [ ] 4. Improve `SupabaseService` placeholder handling: misconfiguration surfaces
      immediately (assertionFailure in Debug; user-visible config-error state instead
      of silent invalid-URL client in Release). (R3)
- [ ] 5. Parameterize the runner function-sync path into a GitHub Actions variable;
      write the runner requirements doc. (R4)
- [ ] 6. Measure current real coverage → set `MIN_COVERAGE` to that floor with the
      ratchet-only comment. (R5)
- [ ] 7. Make `lint_changed_swift.sh` blocking (remove `continue-on-error`), and
      dependency-review fail on critical. (R5)

## Verification

- [ ] Push a branch with an intentionally broken migration → dev/staging workflow fails
      at the migration step (then delete the branch).
- [ ] Attempt a prod deploy from a SHA with a failing test → workflow refuses.
- [ ] Build Release with placeholder xcconfig → build fails with the assertion message;
      with real prod values → passes.
- [ ] Lower a Swift file into a lint violation on a test branch → CI fails.
- [ ] Coverage below the new floor (temporarily exclude a covered file) → CI fails;
      restored → passes.
- [ ] Normal PR flow (`ios-tests.yml` on a clean branch) is green end-to-end.

## Regression Guards

- The typed `deploy-production` confirmation in `deploy-prod.yml` must survive —
  don't automate away the human gate.
- Existing green paths keep working: deno tests for `chat/lib.ts`, the iOS build on the
  self-hosted mac runner (iPhone 17 sim), Sonar + gitleaks jobs.
- Spec 003's reproducible-migration guarantee is what R1 leans on — if a migration
  legitimately needs an idempotency guard, fix the migration, never the pipeline.
