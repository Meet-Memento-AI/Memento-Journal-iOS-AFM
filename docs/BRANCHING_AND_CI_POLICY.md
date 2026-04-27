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

The following checks are expected to be required in repository branch protection settings:

- iOS quality gates
- Deno chat tests
- CodeQL analysis
- Dependency review
- Secret scanning

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

- Pushes to dev trigger automated deployment workflow.
- Deployment runs first to dev environment, then to staging.
- GitHub Environments should enforce reviewer approvals and protect secrets.
- Required deployment secrets:
  - DEV_SUPABASE_ACCESS_TOKEN
  - DEV_SUPABASE_PROJECT_REF
  - STAGING_SUPABASE_ACCESS_TOKEN
  - STAGING_SUPABASE_PROJECT_REF

## Rollout notes

- Keep Periphery non-blocking initially.
- Move Periphery to blocking after baseline cleanup.
- Raise coverage threshold gradually as tests improve.

Quality rollout details: [docs/QUALITY_GATE_ROLLOUT.md](docs/QUALITY_GATE_ROLLOUT.md)
