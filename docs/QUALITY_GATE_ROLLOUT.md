# Quality Gate Rollout Plan

This guide defines safe rollout of strict quality gates without blocking delivery due to historic tech debt.

## Current gate stack

Online merge stack (see [spec 025](../specs/025-ci-online-ios-build-gates.md)):

- Linux constitutional / store gates (`spec-gates.yml`)
- Security: gitleaks, dependency-review, Sonar (`security.yml`)
- **iOS build (online)** (`ios-build-online.yml`): build-spec assert, SwiftLint,
  online unit tests (`CI_ONLINE=1`), coverage, Periphery
- Optional non-blocking: `ios-device-eval.yml` (never a required check)

## Coverage threshold ratcheting

**Current honest floor (2026-09-14):** `MIN_COVERAGE=13` in
`ios-build-online.yml`, measured on the **online** suite (`CI_ONLINE=1`).
The previous 60% / 75–80% schedule below is a **target**, not a live gate —
advertising 60% while enforcing 13% is the class of failure spec 006 forbids.

Suggested schedule *after* a re-measure (spec 052 R2 / 011 R5):
- Re-measure the online suite; set the floor to that integer (only upward).
- Then increase by 2–3% when new suites land, toward a 75–80% **target**.

Rules:
- Never reduce threshold unless CI is proven flaky.
- Keep threshold changes in pull requests with release notes.
- Pair threshold increases with test debt tickets.
- Update this paragraph in the same PR as the workflow `MIN_COVERAGE` value.

## Periphery rollout model

- Phase 1: report and visibility (already active)
- Phase 2: fail only on findings in changed Swift files (active)
- Phase 3: fail on any findings after baseline cleanup milestone

## Baseline cleanup strategy

1. Export and review periphery report artifacts for one week.
2. Create grouped cleanup tasks by module.
3. Remove dead code in small PRs to minimize regressions.
4. After cleanup milestone, remove advisory mode and enforce full blocking.

## Ownership and exceptions

- CODEOWNERS approval required for CI/workflow changes.
- Exceptions are allowed only with explicit reviewer signoff.
- Security checks are not bypassed for convenience.
