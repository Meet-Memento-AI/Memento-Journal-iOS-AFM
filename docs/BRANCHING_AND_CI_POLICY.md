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

The following checks are expected to be required in repository branch protection settings
(online-testable lanes per [spec 025](../specs/025-ci-online-ios-build-gates.md)):

- iOS quality gates → target name **"iOS build (online)"** after spec 025 lands
- Spec gates (2.0) — individual Linux jobs in `spec-gates.yml`
- Dependency review
- Secret scanning

Do **not** require on-device Foundation Models generation, Spotlight device spikes,
or spec 022 Evaluations as merge blockers. CodeQL is not wired in
`.github/workflows/` today — do not list it as required until a workflow exists.

Branch protection setup guide: [docs/BRANCH_PROTECTION_SETUP.md](docs/BRANCH_PROTECTION_SETUP.md)

## Swift quality gates

The project uses Swift-native quality checks as a Sonar-equivalent gate:

- SwiftLint in strict mode
- iOS tests with coverage collection
- Coverage threshold validation
- Periphery dead-code scan (advisory during rollout)

## Security controls in CI

- CodeQL static analysis for Swift and JavaScript.
- Dependency review on pull requests.
- Secret scanning with gitleaks.
- Dependabot updates for GitHub Actions dependencies.

## Deployment policy

The product is **on-device only** — there is no backend deploy pipeline in the
current workflow set (`ios-tests.yml`, `security.yml`, `spec-gates.yml`). Store
upload / TestFlight remain manual operator steps (`docs/app-store/`).

## Rollout notes

- Keep Periphery non-blocking initially.
- Move Periphery to blocking after baseline cleanup.
- Raise coverage threshold gradually as tests improve.

Quality rollout details: [docs/QUALITY_GATE_ROLLOUT.md](docs/QUALITY_GATE_ROLLOUT.md)
