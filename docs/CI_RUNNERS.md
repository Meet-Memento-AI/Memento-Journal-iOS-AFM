# CI Runners

MeetMemento's GitHub Actions run on **self-hosted runners**. This document records
what they must provide so a runner can be rebuilt or replaced (spec-006).

The app is **on-device only** — no accounts, no backend, no Supabase. CI therefore
builds and tests the iOS app and runs security/governance gates; there are no
deploy jobs and no Deno/edge-function tests.

## Online vs on-device (spec 025)

Merge CI must stay honest **without** a provisioned Apple Intelligence model.
Full matrix and acceptance criteria: [`specs/025-ci-online-ios-build-gates.md`](../specs/025-ci-online-ios-build-gates.md).

| Lane | Required to merge? | Runner | Proves |
|------|--------------------|--------|--------|
| Spec gates (2.0) + store hygiene | Yes | Linux | Constitution / App Store machine checks, fixture corpus |
| Security | Yes | Linux | Sonar, gitleaks, dependency-review |
| iOS build (online) | Yes | macOS + Xcode 26+ | Build specs + mockable unit tests; **not** live FM generation |
| Device / eval (022, spikes, FM generation) | No | Local device or optional workflow | On-device model, Spotlight spikes, Evaluations harness |

**iOS build specifications (online job contract):** scheme `MeetMemento`;
destination `platform=iOS Simulator,name=iPhone 17,OS=latest` (overridable);
`IPHONEOS_DEPLOYMENT_TARGET >= 26.0`; UITests skipped; device-gated generation
suites skipped by policy.

## Runner labels

| Label set | Used by | Purpose |
|-----------|---------|---------|
| `[self-hosted, macOS, ARM64, ios, xcode]` | `ios-tests.yml` (ios-unit-ui) | Xcode build + unit tests, coverage, SwiftLint, Periphery |
| `[self-hosted, Linux, x64]` | `security.yml`, `spec-gates.yml` | Sonar, gitleaks, dependency review, and the SDK-free spec gates |

## Required software

**macOS runner:** Xcode **26+** (the Foundation Models SDK is required to build the
on-device intelligence layer) with an iOS simulator runtime installed (workflows
target `iPhone 17, OS=latest`; override via the `IOS_DEVELOPER_DIR` /
`IOS_SIM_DESTINATION` repo variables), Homebrew, SwiftLint, Periphery.

**Linux runner:** `sonar-scanner`, `gitleaks`, Python 3 (spec gates). No Docker, no
Supabase CLI, no Deno.

## Repository variables (optional)

| Variable | Meaning | Default if unset |
|----------|---------|------------------|
| `IOS_DEVELOPER_DIR` | `DEVELOPER_DIR` path to the Xcode used for the iOS build | `/Applications/Xcode.app/Contents/Developer` |
| `IOS_SIM_DESTINATION` | `xcodebuild -destination` string | `platform=iOS Simulator,name=iPhone 17,OS=latest` |

## Required secrets

`SONAR_TOKEN` (+ the `SONAR_PROJECT_KEY` / `SONAR_HOST_URL` variables) for the Sonar
scan in `security.yml`. Nothing else — the build needs no API keys.

## What breaks when a runner is offline

- **macOS runner down** → `ios-tests.yml` can't run (build/test/coverage). No merge
  gate passes until it's back.
- **Linux runner down** → no Sonar/gitleaks/dependency-review and no spec gates.
- There is **no GitHub-hosted fallback** today (tracked in spec 012). If a runner is
  permanently lost, provision a replacement with the software above and re-register it
  with the matching labels.
