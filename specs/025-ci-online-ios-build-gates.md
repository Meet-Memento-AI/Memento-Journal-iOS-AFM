---
id: 025
title: CI Focused on Online-Testable iOS Build Gates
tier: P1
status: not-started
effort: 1-2 sessions
depends_on: [006]
findings: [ci-couples-merge-to-on-device-model, ios-workflow-monolith, device-gated-suites-in-pr-path, no-online-build-matrix, runner-fallback-undocumented]
tech_refs: [technology/09-ui-swift6-testing.md, technology/04-evaluations.md]
---

# 025 — CI Focused on Online-Testable iOS Build Gates

## Why

Merge CI today treats the self-hosted macOS + simulator path as the primary quality
signal, even though **on-device Foundation Models generation cannot be proven in that
environment** (`IntelligenceServiceTests` already `XCTSkip`s when the model is
unavailable or returns `LanguageModelError -1`). Spec gates and security jobs already
prove the online-testable half of the constitution on Linux. This spec re-centers
CI/CD on **iOS build specifications and suites that are honest online**, and moves
model-dependent evaluation to an explicit local / optional device lane — so a green
PR means "this SHA builds and the checkable gates hold," not "a personal Mac with
Apple Intelligence happened to be online."

Blocks honest Gate S / branch-protection required checks. Harvests the runner-strategy
intent of spec 012 item 8 without waiting for a full GitHub-hosted migration.

## Technology References

- `specs/reference/technology/09-ui-swift6-testing.md` — what is unit-testable vs
  device/instrument-only (availability simulation, FM instrument, App Intents).
- `specs/reference/technology/04-evaluations.md` — five named eval gates; local-only
  harness contract owned by spec 022 (stays out of merge CI until automatable
  without a provisioned model).

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | Single macOS job owns lint, build, unit tests, coverage, Periphery; required check name is "iOS quality gates." Failure of the runner or of a device-gated suite blocks merges unrelated to build integrity. | `.github/workflows/ios-tests.yml`; `docs/BRANCH_PROTECTION_SETUP.md` | HIGH |
| 2 | On-device generation tests run in the same `xcodebuild test` invocation as security/unit suites, then skip — noise in CI logs; coverage floor comments still advertise "on-device Intelligence suites" as if CI exercised generation. | `MeetMementoTests/IntelligenceServiceTests.swift:21-49`; `ios-tests.yml:78-87` | MEDIUM |
| 3 | Env-gated Spotlight spikes (`TEST_RUNNER_SPIKE_A/C`) correctly skip in CI, but there is no documented "online vs device" test matrix for contributors or branch protection. | `SpikeA_*.swift`, `SpikeC_*.swift`; `docs/CI_RUNNERS.md` | MEDIUM |
| 4 | Spec 022's five eval gates and FM instrument work are **local / device** by design; no workflow yet separates "merge CI" from "eval nightlies." | `specs/022-evaluation-and-quality-study.md` R1–R2 | MEDIUM |
| 5 | Linux `spec-gates.yml` + `security.yml` already encode the online constitutional ladder, but docs still describe deployment-era secrets and list CodeQL as required while no CodeQL workflow exists in-tree. | `docs/BRANCHING_AND_CI_POLICY.md`; `docs/BRANCH_PROTECTION_SETUP.md`; `.github/workflows/` (3 files) | MEDIUM |
| 6 | iOS **build** specs are implicit in comments (`Xcode 26+`, `iPhone 17`, `OS=latest`, scheme `MeetMemento`, `IPHONEOS_DEPLOYMENT_TARGET = 26.0`) with no single CI job that asserts them as a contract. | `project.pbxproj`; `ios-tests.yml:17-26`; `README.md` | MEDIUM |

## Online vs on-device matrix (source of truth for this spec)

### A. Online-testable (merge CI — must stay green without Apple Intelligence)

| Lane | Runner | What it proves |
|------|--------|----------------|
| **Constitutional / store** | Linux (`spec-gates.yml`) | Single FM importer; forbidden phrases; speakability selftest; dependency allowlist; privacy manifest; Info.plist / build-number hygiene; archive hygiene; ASC metadata; fixture corpus + gold sync |
| **Security** | Linux (`security.yml`) | Sonar (when configured); gitleaks; dependency-review on PRs |
| **iOS build contract** | macOS with Xcode 26+ SDK (self-hosted today; GitHub-hosted `macos-*` when available) | Scheme `MeetMemento` **builds** for `platform=iOS Simulator` with pinned `DEVELOPER_DIR` / destination vars; deployment target ≥ 26.0; Debug test build succeeds |
| **iOS unit / seam tests** | Same macOS job | Suites that use mocks / pure logic / local storage seams — no live `LanguageModelSession` generation. Includes encryption, security, app-state, journal, retrieval policy, turn classifier, prompt stance/personalization, conversation flow, chat VM with `MockIntelligenceService`, corpus-adjacent unit tests, etc. |
| **Static Swift quality** | Same macOS job (or split) | Changed-file SwiftLint (blocking on PR); Periphery regression on PR; coverage ratchet over the **online** suite only |

### B. On-device / local-only (not a merge blocker)

| Lane | Where | What it proves |
|------|-------|----------------|
| Live FM generation | Physical Apple Intelligence device (or sim only if Apple later makes generation real) | `IntelligenceServiceTests` ask/summarize paths |
| Spotlight spikes | Device + env flags | Spike A / Spike C (`DEC-002`) |
| Eval harness (022) | Local Xcode + `Evaluations`; optional scheduled workflow on a capable Mac | RetrievalGate, GroundingGate (automatable half), PersonaGate, LatencyGate checkpoint, DegradationGate |
| Availability matrix | Xcode "Simulate Apple Foundation Models Availability" | Reduced-tier / unavailable UX |
| UITests | Local or future hardened sim job | Launch/smoke — still `-skip-testing` in merge CI (012 #3) |
| Liquid Glass / system UI | Device | Rendering fidelity (tech note 12) |

## iOS build specifications (CI contract)

Pin and assert these in the online iOS workflow (fail the job if unmet):

| Spec | Value | Enforcement |
|------|-------|-------------|
| Xcode major | **26+** (Foundation Models SDK present to *compile*) | `xcodebuild -version` gate step |
| Scheme | `MeetMemento` | `xcodebuild -scheme MeetMemento …` |
| Destination | `platform=iOS Simulator,name=iPhone 17,OS=latest` (overridable via `IOS_SIM_DESTINATION`) | env + first step echo |
| Deployment target | `IPHONEOS_DEPLOYMENT_TARGET >= 26.0` | script or `xcodebuild -showBuildSettings` assertion |
| Test configuration | Debug | scheme TestAction |
| UITests in merge CI | **skipped** | `-skip-testing:MeetMementoUITests` |
| Device-gated unit tests in merge CI | **skipped** | `-skip-testing` list or Swift test plan / env (`CI_ONLINE=1`) — see R2 |
| Secrets / xcconfig | none required | document; fail if workflow reintroduces backend deploy keys |
| Coverage floor | ratchet-only; measured on online suites | `MIN_COVERAGE` comment + `check_coverage.sh` |

Compile-with-SDK ≠ run-the-model: the macOS job must keep building the Intelligence
boundary (single importer still compiles), but must not require a provisioned model
to go green.

## Requirements

### R1. Split merge CI into online lanes with explicit ownership
**Acceptance:** Documentation and workflows name three merge-critical lanes —
(1) `spec-gates`, (2) `security`, (3) `ios-build-online` — and state that none of
them require on-device FM generation. Branch-protection docs list the real check
names present in `.github/workflows/` (no phantom CodeQL / deploy secrets for the
on-device-only product). `docs/CI_RUNNERS.md` describes the matrix in §"Online vs
on-device" above.

### R2. iOS merge job proves build + online tests only
**Acceptance:** `ios-tests.yml` (or a renamed workflow) on PR/push:

1. Asserts the iOS build specifications table (Xcode version, scheme, destination,
   deployment target).
2. Runs `xcodebuild test` with UITests skipped **and** device-gated suites skipped
   (minimum: `IntelligenceServiceTests` generation cases; spikes already env-gated).
   Preferred mechanism: a shared test plan or `CI_ONLINE=1` early-skip in those
   classes so skips are intentional, not "failed then XCTSkip."
3. Coverage gate uses a floor measured after the skip list is stable; comment
   records that the floor is for the online suite, not FM generation.
4. SwiftLint changed-files + Periphery PR regression remain as today.

### R3. Device / eval work has a non-blocking home
**Acceptance:** A documented lane (workflow_dispatch and/or `schedule`,
`continue-on-error: true` or separate non-required check) exists for
"on-device / eval" work: either a stub workflow that documents the local commands
from README + spec 022, or a real optional job that runs without `-skip-testing`
the device suites when `vars.IOS_DEVICE_EVAL=1`. Merge to `dev`/`main` must not
require this check. Spec 022 remains owner of harness implementation.

### R4. Policy docs match the on-device-only product
**Acceptance:** `docs/BRANCHING_AND_CI_POLICY.md` and
`docs/BRANCH_PROTECTION_SETUP.md` drop stale Supabase deploy-secret requirements
and any required check that has no workflow file; they require the three online
lanes from R1 (including Spec gates 2.0). `README.md` Testing/CI section points
at the online vs device matrix.

### R5. No regression of constitutional Linux gates
**Acceptance:** All jobs in `spec-gates.yml` remain present and blocking where they
are blocking today; this spec only adds clarity and the iOS online split — it does
not weaken privacy/store/corpus gates.

## Out of Scope

- Implementing spec 022's five Evaluations gates → **spec 022**.
- Re-enabling UITests as blocking → **spec 012 #3**.
- Full migration off self-hosted runners to GitHub-hosted (cost decision) → remains
  parked under 012 #8; this spec only requires the **contract** to be runnable on
  any Mac with Xcode 26+ so a hosted runner can be swapped in later.
- Raising coverage via new product tests → **spec 011** (this spec may re-measure
  the floor after skips stabilize).
- Changing Intelligence architecture or the single-importer rule → **spec 017**.

## Tasks

- [ ] 1. Write the online vs on-device matrix into `docs/CI_RUNNERS.md` and trim
      stale deploy/CodeQL claims from branching + branch-protection docs. (R1, R4)
- [ ] 2. Add an iOS build-spec assertion step/script
      (`scripts/ci/assert_ios_build_specs.sh`) covering Xcode major, scheme list,
      deployment target, and destination echo. (R2)
- [ ] 3. Introduce intentional online skipping for device-gated tests
      (`CI_ONLINE=1` and/or `-skip-testing` / test plan); keep availability-path
      coverage that does not call generation if it can stay green without a model.
      (R2)
- [ ] 4. Restructure `ios-tests.yml`: build-spec assert → lint → online test →
      coverage → Periphery; update job/check display name to
      **"iOS build (online)"** (or keep "iOS quality gates" only if branch
      protection is updated in the same change). (R2)
- [ ] 5. Add `ios-device-eval.yml` (dispatch/schedule, non-required) that documents
      or optionally runs device/eval commands; link from README. (R3)
- [ ] 6. Re-measure `MIN_COVERAGE` on the online suite; adjust floor only upward
      or document why an equal floor remains valid after excluding skips. (R2, 011)
- [ ] 7. Update `ROADMAP.md` / quality-rollout notes; mark 012 #8 as partially
      addressed (contract ready for hosted runners; migration still parked). (R1)

## Verification

- [ ] On a PR with no model: online iOS job is green; Linux spec-gates + security
      green; logs show device suites **skipped by policy**, not failed-then-skip.
- [ ] Planted failures: lower deployment target in pbxproj → build-spec script
      fails; break `check_privacy_manifest.sh` precondition → spec-gates fails;
      add a new `import FoundationModels` outside Intelligence → importer gate fails.
- [ ] `bash -n` on new/changed `scripts/ci/*.sh`; workflow YAML parses.
- [ ] Branch-protection doc check names match `jobs.*.name` in the three merge
      workflows exactly.
- [ ] Optional device workflow does not appear as a required check.

## Regression Guards

- CONSTITUTION § CI / single Intelligence importer: Linux importer gate stays
  blocking; app still compiles the FM boundary on the macOS job.
- Spec 006 honesty: no advisory-as-blocking theater; coverage floor remains
  ratchet-only and reflects what CI actually runs.
- Spec 014 / store gates: privacy manifest, ASC metadata, archive hygiene
  unchanged in severity.
- Spec 022: eval harness stays local-first; do not force PCC/Z1 into merge CI.
- Frontend preservation: no product UI changes in this spec.
