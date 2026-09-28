# CI Runners

withMemento's merge CI runs on **GitHub-hosted runners** (since 2026-09-23). This
document records what each lane needs (spec-006 / spec-025).

**Why not self-hosted.** Until 2026-09-23 every lane targeted self-hosted runners.
None were registered, so every job sat in *queued* until GitHub cancelled it, and
for weeks no gate ran at all. This repository is **public**, which makes hosted
runners (macOS included) free, and makes self-hosted runners unsafe: a fork's
pull request would execute on our own machine.

CI builds and tests the iOS app and runs security/governance gates; there are no
backend deploy jobs. Journal data is on-device only; the one backend is the
opt-in feedback endpoint (spec 042), which CI never calls.

The intended **store** CD job (archive / validate / TestFlight) is specified in
[`docs/CICD_PIPELINE.md`](CICD_PIPELINE.md) and spec 052. Merge CI stays on
hosted runners; release signing will use an `app-store` GitHub Environment and
must not run on `pull_request` from forks.

## Online vs on-device (spec 025)

Merge CI must stay honest **without** a provisioned Apple Intelligence model.
Executable plan/acceptance: [`specs/025-ci-online-ios-build-gates.md`](../specs/025-ci-online-ios-build-gates.md).

| Lane | Workflow | Required to merge? | Runner | Proves |
|------|----------|--------------------|--------|--------|
| Spec gates (2.0) + store hygiene | `spec-gates.yml` | Yes | `ubuntu-latest` | Constitution / App Store machine checks, fixture corpus |
| Security | `security.yml` | Yes | `ubuntu-latest` | gitleaks, dependency-review; Sonar when configured |
| iOS build (online) | `ios-build-online.yml` | Yes | `xcode-27` (hosted) | Build specs + mockable unit tests + size gate; **not** live FM generation |
| Device / eval | `ios-device-eval.yml` | **No** | self-hosted macOS (optional) | On-device model, Spotlight spikes, Evaluations harness |

**iOS build specifications (online job contract):** scheme `withMemento`;
destination `platform=iOS Simulator,name=iPhone 17,OS=latest` (overridable);
`IPHONEOS_DEPLOYMENT_TARGET >= 26.0`; UITests skipped; device-gated generation
suites skipped by `CI_ONLINE=1` (asserted by `scripts/ci/assert_ios_build_specs.sh`).

## Runners

| Runner | Used by | Notes |
|--------|---------|-------|
| `ubuntu-latest` | `spec-gates.yml`, `security.yml` | Python 3, curl, git preinstalled; gitleaks installed per run |
| `xcode-27` | `ios-build-online.yml` | GitHub's Xcode 27 image ([runner-images#14404](https://github.com/actions/runner-images/issues/14404)), still a *preview* label. The Xcode 26.x images **cannot compile the app** (iOS 27 FoundationModels APIs). Swap to the GA label via the `IOS_RUNNER` variable when it ships |
| `[self-hosted, macOS, ARM64, ios, xcode]` | `ios-device-eval.yml` only | Advisory lane; needs Apple Intelligence hardware, which hosted runners lack. Never trigger it from `pull_request` — this repo is public |

### Device classes for model evals (spec 051 R6)

iOS 27 runs one of two on-device models, and quality differs by model, so an
eval run must say which one answered. Every generation's `model_identifier`
now carries the tier (`apple.system.on-device.afm3-core-advanced`,
`.afm3-core`, `.pre-afm3`), and the perf line logs `tier=` / `tier_source=`.

| Device class | Example | Model | Needed for |
|---|---|---|---|
| 12 GB or more | iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air | AFM 3 Core Advanced (20B, sparse) | Core Advanced quality and TTFT; the only evidence that may move its latency clamps (spec 051 R5) |
| 8 GB | iPhone 17, iPhone 16 | AFM 3 Core (3B) | The Core baseline every other spec's numbers were tuned on |

Run a physical-device eval on one device of each class. A **simulator** run
uses the host Mac's model and reports the host's memory, so its tier describes
the Mac, not a phone: label it with whatever the resolver reported and never
compare it across tiers. The tier on these rows is inferred from OS and memory
(`tier_source=inferred`) until spec 051 R0 finds an SDK member that reports it.

**Git LFS.** The ~148 MB of Core ML voice weights are LFS objects. The iOS job
caches `.git/lfs` keyed on the object ids, so the quota is spent once per weights
change rather than once per run, and it fails fast if any pointer file survives.

## Repository variables (optional)

| Variable | Meaning | Default if unset |
|----------|---------|------------------|
| `IOS_RUNNER` | `runs-on` label for the iOS build | `xcode-27` |
| `IOS_DEVELOPER_DIR` | `DEVELOPER_DIR` path to the Xcode used for the iOS build | `/Applications/Xcode.app/Contents/Developer` |
| `IOS_SIM_DESTINATION` | `xcodebuild -destination` string | `platform=iOS Simulator,name=iPhone 17,OS=latest` |

## Required secrets

None are required. `SONAR_TOKEN` (+ the `SONAR_PROJECT_KEY` variable, and
`SONAR_HOST_URL` if not SonarCloud) turns on the Sonar scan in `security.yml`;
without them the job passes with a notice instead of failing. The build needs no
API keys.

## What breaks when a runner is unavailable

- **`xcode-27` preview capacity** can queue for a while (GitHub's note on the
  preview). A job that is merely slow is fine; if the label is withdrawn, set
  `IOS_RUNNER` to its successor rather than editing the workflow.
- **Self-hosted device lane down** → only `ios-device-eval.yml` is affected, and it
  is advisory.
