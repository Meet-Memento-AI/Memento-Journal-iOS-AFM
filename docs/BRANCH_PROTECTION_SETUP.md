# GitHub Branch Protection Setup

Use this checklist to enforce the main + dev model and required CI/CD security gates.

## Prerequisites

- Push the dev branch to origin.
- Ensure workflows exist in default branch:
  - .github/workflows/ios-tests.yml
  - .github/workflows/security.yml
  - .github/workflows/deploy-dev-staging.yml

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

Add required status checks:
- iOS quality gates
- Deno edge-function tests
- CodeQL analysis
- Dependency review
- Secret scanning

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

Add required status checks:
- iOS quality gates
- Deno edge-function tests
- CodeQL analysis
- Dependency review
- Secret scanning

## Merge policy

- Feature branches target dev.
- Only release promotion PRs should target main (dev -> main).
- Direct commits to dev/main should be blocked.

## Environments and deployment secrets

If using repository environments, create:
- dev
- staging

Set secrets for each target (or repository secrets if not using environments):
- DEV_SUPABASE_ACCESS_TOKEN
- DEV_SUPABASE_PROJECT_REF
- STAGING_SUPABASE_ACCESS_TOKEN
- STAGING_SUPABASE_PROJECT_REF

Recommendation:
- Require reviewers for staging environment deployments.
- Keep production deployment manual in this phase.

## Verification script

Run these checks after configuration:
1. Open a PR from feature branch to dev and verify merge is blocked until all checks pass.
2. Open a PR from dev to main and verify required checks and approval gates are enforced.
3. Attempt direct push to dev and main and confirm it is rejected.
4. Merge a PR to dev and verify deploy-dev-staging workflow runs.
