# GitHub Branch Protection Setup

Use this checklist to enforce the main + dev model and required online CI gates
([spec 025](../specs/025-ci-online-ios-build-gates.md)).

## Prerequisites

- Push the `dev` branch to origin.
- Ensure merge workflows exist on the default branch:
  - `.github/workflows/ios-build-online.yml`
  - `.github/workflows/security.yml`
  - `.github/workflows/spec-gates.yml`
- Optional (never required): `.github/workflows/ios-device-eval.yml`

## Required branch rules: dev

Navigate to GitHub repository settings:
- Settings -> Branches -> Add branch protection rule
- Branch name pattern: `dev`

Enable these options:
- Require a pull request before merging
- Require approvals: 1
- Dismiss stale pull request approvals when new commits are pushed
- Require status checks to pass before merging
- Require conversation resolution before merging
- Do not allow bypassing the above settings
- Restrict who can push to matching branches (optional, recommended)

Add required status checks (names must match `jobs.*.name`):

- `iOS build (online)`
- Spec-gates job names you choose to require from `spec-gates.yml` (e.g. privacy
  manifest, store metadata, corpus validation, single importer)
- `Dependency review`
- `Secret scanning`

Remove any stale required check named `iOS quality gates` (replaced by
`iOS build (online)`). Do not require `iOS device / eval`.

## Required branch rules: main

Same options as `dev`, plus:

- Require branches to be up to date before merging
- Restrict who can push to matching branches

Required status checks: same online set as `dev`.

## Merge policy

- Feature branches target `dev`.
- Only release promotion PRs should target `main` (`dev` -> `main`).
- Direct commits to `dev`/`main` should be blocked.

## Environments and secrets

No Supabase/deploy environments are required for the on-device product. For
`security.yml` Sonar analysis, configure `SONAR_TOKEN` plus
`SONAR_PROJECT_KEY` / `SONAR_HOST_URL` as documented in `docs/CI_RUNNERS.md`.

## Verification script

Run these checks after configuration:
1. Open a PR from a feature branch to `dev` and verify merge is blocked until
   online checks pass.
2. Open a PR from `dev` to `main` and verify required checks and approval gates.
3. Attempt a direct push to `dev` and `main` and confirm it is rejected.
4. Merge a PR to `dev` and verify `ios-build-online`, `security`, and
   `spec-gates` run; confirm `ios-device-eval` is not required.
