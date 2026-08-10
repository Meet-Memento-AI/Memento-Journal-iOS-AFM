# GitHub Branch Protection Setup

Use this checklist to enforce the main + dev model and required CI/CD security gates.

## Prerequisites

- Push the dev branch to origin.
- Ensure workflows exist in default branch:
  - .github/workflows/ios-tests.yml
  - .github/workflows/security.yml
  - .github/workflows/spec-gates.yml

## Required branch rules: dev

Navigate to GitHub repository settings:
- Settings -> Branches -> Add branch protection rule
- Branch name pattern: dev

Enable these options:
- Require a pull request before merging
- Require approvals: 1
- Dismiss stale pull request approvals when new commits are pushed
- Require status checks to pass before merging
- Require conversation resolution before merging
- Do not allow bypassing the above settings
- Restrict who can push to matching branches (optional, recommended)

Add required status checks (online lanes only — [spec 025](../specs/025-ci-online-ios-build-gates.md)):
- iOS quality gates (rename to **iOS build (online)** when 025 lands)
- Spec gates jobs you choose to require from `spec-gates.yml`
- Dependency review
- Secret scanning

Do not require device/eval workflows or checks that need a provisioned on-device model.

## Required branch rules: main

Navigate to GitHub repository settings:
- Settings -> Branches -> Add branch protection rule
- Branch name pattern: main

Enable these options:
- Require a pull request before merging
- Require approvals: 1 (or 2 for stricter policy)
- Dismiss stale pull request approvals when new commits are pushed
- Require status checks to pass before merging
- Require conversation resolution before merging
- Require branches to be up to date before merging
- Do not allow bypassing the above settings
- Restrict who can push to matching branches

Add required status checks (same online set as `dev`):
- iOS quality gates (rename to **iOS build (online)** when 025 lands)
- Spec gates jobs you choose to require from `spec-gates.yml`
- Dependency review
- Secret scanning

## Merge policy

- Feature branches target dev.
- Only release promotion PRs should target main (dev -> main).
- Direct commits to dev/main should be blocked.

## Environments and secrets

No Supabase/deploy environments are required for the on-device product. For
`security.yml` Sonar analysis, configure `SONAR_TOKEN` plus
`SONAR_PROJECT_KEY` / `SONAR_HOST_URL` as documented in `docs/CI_RUNNERS.md`.

## Verification script

Run these checks after configuration:
1. Open a PR from feature branch to dev and verify merge is blocked until all checks pass.
2. Open a PR from dev to main and verify required checks and approval gates are enforced.
3. Attempt direct push to dev and main and confirm it is rejected.
4. Merge a PR to dev and verify ios-tests, security, and spec-gates workflows run.
