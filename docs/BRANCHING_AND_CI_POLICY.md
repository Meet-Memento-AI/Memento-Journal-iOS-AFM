# Branching and CI Policy

## Branch model

- main: production-ready branch.
- dev: integration branch for upcoming releases.
- feature branches: branch from dev and merge back into dev through pull requests.
- promotion: merge dev into main through a dedicated pull request after validation.

## Merge policy

- No direct pushes to main.
- No direct pushes to dev.
- All changes must go through pull requests.
- All required checks must pass before merge.
- At least one approving review is required.

## Required checks

Online-testable lanes only ([spec 025](../specs/025-ci-online-ios-build-gates.md)):

- **iOS build (online)** — `ios-build-online.yml`
- Spec gates (2.0) — jobs in `spec-gates.yml`
- Dependency review — `security.yml`
- Secret scanning — `security.yml`

Do **not** require `ios-device-eval.yml`, on-device Foundation Models generation,
Spotlight device spikes, or spec 022 Evaluations as merge blockers.

Branch protection setup guide: [docs/BRANCH_PROTECTION_SETUP.md](docs/BRANCH_PROTECTION_SETUP.md)

## Swift quality gates (online iOS job)

- iOS build-specification assertion (`scripts/ci/assert_ios_build_specs.sh`)
- SwiftLint in strict mode (changed files blocking on PR)
- Online unit tests with `CI_ONLINE=1` (UITests + live FM generation skipped)
- Coverage threshold validation (ratchet-only over the online suite)
- Periphery dead-code scan (advisory report + PR regression gate)

## Security controls in CI

- Dependency review on pull requests (fail on critical).
- Secret scanning with gitleaks.
- Sonar analysis when `SONAR_TOKEN` / project vars are configured.
- Dependabot updates for GitHub Actions dependencies.

## Deployment policy

The product is **on-device only** — there is no backend deploy pipeline in the
current workflow set (`ios-build-online.yml`, `security.yml`, `spec-gates.yml`,
optional `ios-device-eval.yml`). Store upload / TestFlight remain manual operator
steps (`docs/app-store/`).

## Rollout notes

- Keep Periphery non-blocking for the full scan; PR regression gate is blocking.
- Raise coverage threshold gradually as online tests improve.
- Device/eval remains optional until hardware + spec 022 harness are ready.

Quality rollout details: [docs/QUALITY_GATE_ROLLOUT.md](docs/QUALITY_GATE_ROLLOUT.md)
