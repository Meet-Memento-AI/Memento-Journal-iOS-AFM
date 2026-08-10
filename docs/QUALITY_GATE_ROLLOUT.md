# Quality Gate Rollout Plan

This guide defines safe rollout of strict quality gates without blocking delivery due to historic tech debt.

## Current gate stack

Online merge stack (see [spec 025](../specs/025-ci-online-ios-build-gates.md)):

- Linux constitutional / store gates (`spec-gates.yml`)
- Security: gitleaks, dependency-review, Sonar
- SwiftLint strict mode on changed files (blocking on PR)
- iOS **build specifications** + online unit tests (blocking; not live FM generation)
- Coverage gate at baseline threshold (blocking; ratchet-only over the online suite)
- Periphery scan report (artifact)
- Periphery regression gate on changed Swift files only (blocking on PR)

## Coverage threshold ratcheting

Start with a conservative threshold and increase gradually.

Suggested schedule:
- Week 1-2: 60%
- Week 3-4: 62%
- Week 5-6: 65%
- Then increase by 2-3% every month until target range (75-80%)

Rules:
- Never reduce threshold unless CI is proven flaky.
- Keep threshold changes in pull requests with release notes.
- Pair threshold increases with test debt tickets.

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
