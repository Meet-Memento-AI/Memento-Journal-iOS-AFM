---
id: 046
title: CI/CD Pipeline and Release Automation
tier: P1
status: not-started
effort: 3 sessions (A honesty, B test plan, C archive/validate/TestFlight)
depends_on: [006, 025]
findings: [no-release-automation, no-altool-validate-in-ci, no-xctestplan, uitests-skipped, coverage-doc-drift, sonar-hard-fail, single-sim-destination, watch-unbuilt, storekit-enforce-off]
tech_refs: [technology/09-ui-swift6-testing.md, technology/04-evaluations.md]
---

# 046 — CI/CD Pipeline and Release Automation

## Why

Merge CI already proves **online-testable** integrity (specs 006, 025). Releases
do not: archive/export/validate/TestFlight are still manual, export has never
completed, and several “quality” docs describe floors the pipeline does not
enforce. Before Gate T (external TestFlight) the path from a green `main` SHA to
a **validated App Store IPA** must be scripted, Apple-shaped, and honest — same
artifact promoted, GA Xcode only, human Submit.

The operator map (inventory, principles, test matrix) lives at
[`docs/CICD_PIPELINE.md`](../docs/CICD_PIPELINE.md). This spec is the executable
half.

## Technology References

- `specs/reference/technology/09-ui-swift6-testing.md` — unit vs
  device/instrument-only; availability simulation; what belongs in an XCTest plan.
- `specs/reference/technology/04-evaluations.md` — five named eval gates; keep
  them **out** of merge CI until they run without a provisioned model.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | No release automation: no archive/export/validate/upload workflow; headless signing unspecified | `docs/app-store/07-build-signing-and-upload.md` §intro, §7; no `.github/workflows/release-*.yml` | HIGH |
| 2 | `altool --validate-app` has never completed in this project; export blocked on Distribution cert vs store profile | `docs/app-store/00-readiness-checklist.md` C3 | HIGH |
| 3 | Merge iOS job tests Debug simulator only; size gate is simulator Release, not a device archive | `.github/workflows/ios-build-online.yml` test + size steps | HIGH |
| 4 | No shared XCTest plan; skip policy is CLI `-skip-testing` + `CI_ONLINE=1` | `ios-build-online.yml`; no `*.xctestplan` in repo | MEDIUM |
| 5 | UITests exist (launch, onboarding/PIN, chat, TTS, upgrade) but are skipped in merge and device-eval | both iOS workflows `-skip-testing:MeetMementoUITests` | MEDIUM |
| 6 | Single destination `iPhone 17`; Watch target not on merge scheme; iPad unbuilt in CI | `docs/CI_RUNNERS.md`; ROADMAP DEC-005 | MEDIUM |
| 7 | Coverage floor 13% while `QUALITY_GATE_ROLLOUT.md` advertises 60%+ | `ios-build-online.yml` `MIN_COVERAGE`; `docs/QUALITY_GATE_ROLLOUT.md` | MEDIUM |
| 8 | Sonar job exits 1 if `SONAR_TOKEN` / project key missing — couples merge to a personal scanner | `security.yml` “Validate Sonar configuration” | MEDIUM |
| 9 | `STOREKIT_ENFORCE=0` on archive-hygiene; IAP placeholders would not fail merge | `spec-gates.yml` archive-hygiene env | MEDIUM |
| 10 | Branch-protection rename (`iOS quality gates` → `iOS build (online)`) still a user action | spec 025 verification; `docs/BRANCH_PROTECTION_SETUP.md` | MEDIUM |
| 11 | Eval / Gate V / Instruments stay local; device workflow documents 022 commands but does not produce artifacts | `ios-device-eval.yml`; spec 022 | LOW |
| 12 | Dependabot covers GitHub Actions only | `.github/dependabot.yml` | LOW |

## Requirements

### R1. Operator map is the source of truth for *what* to build
**Acceptance:** `docs/CICD_PIPELINE.md` lists live lanes, gaps, target lanes,
secrets, and the test matrix. This spec’s tasks only implement that map; they do
not invent a second pipeline. Apple principles in that doc §1 are non-negotiable
(GA Xcode, validate-before-upload, one artifact, honest green, no crash SDK,
human Submit).

### R2. Merge CI stays online-only and gets cheaper / less brittle
**Acceptance:**

- All four existing workflows gain `concurrency` (PR = cancel in-progress).
- Sonar does not fail the security workflow when unset (skip or advisory).
- A Linux job fails if vendored model/weight paths are LFS pointer files.
- `CODEOWNERS` includes `scripts/ci/` and `docs/app-store/`.
- `MIN_COVERAGE` is re-measured and only increased; `QUALITY_GATE_ROLLOUT.md`
  matches the real floor (delete the fictional 60% schedule or mark it target).
- Skip policy moves into `MeetMemento.xctestplan` **Online** vs **Device**;
  `ios-build-online.yml` uses the Online configuration.

### R3. Nightly proves destinations merge CI cannot
**Acceptance:** A non-required workflow (extend `ios-device-eval.yml` or add
`ios-nightly.yml`) on schedule:

- Launch UITest (`MeetMementoUITestsLaunchTests`) on iPhone sim.
- `xcodebuild build` for an iPad sim destination.
- `xcodebuild build` for the Watch scheme/target if present.
- Still `continue-on-error` or a distinct check name **never** added to branch
  protection.

### R4. Release workflow archives, validates, and uploads TestFlight internal
**Acceptance:** `.github/workflows/release-ios.yml`:

- Triggers: `workflow_dispatch` and tags `v*` from `main` only.
- Uses GitHub Environment `app-store` (required reviewer).
- Refuses to run unless Checks API shows the online merge lanes succeeded on
  that SHA (reuse spec 006’s deploy-prod pattern; there is no backend deploy).
- Asserts GA Xcode (version string must not contain `beta` / `Beta`).
- `archive` for `generic/platform=iOS` Release; export via
  `docs/app-store/ExportOptions.plist`; `altool --validate-app` zero ITMS;
  upload **internal** TestFlight only.
- Asserts archived Info.plist + bundle hygiene + matching dSYM UUIDs.
- Does **not** submit for App Review, change availability, or set phased
  release.

Signing: `-allowProvisioningUpdates` + ASC API key **or** documented manual
signing on the self-hosted Mac. Secrets never enter the repo.

### R5. Human release policy is encoded, not automated away
**Acceptance:** `docs/BRANCHING_AND_CI_POLICY.md` and `docs/CICD_PIPELINE.md` §7
state: feature→`dev`→`main`; 1.0 manual release; updates phased; rollback =
pause phase or hotfix build. `docs/BRANCH_PROTECTION_SETUP.md` verification
checkboxes for the renamed required checks are still the operator closeout
(this spec cannot flip GitHub settings).

### R6. Eval and device generation remain non-blocking
**Acceptance:** No new required check depends on Foundation Models generation,
Spotlight spikes, or spec 022/036 device numbers. When the 022 harness writes
fixture generations, nightly may run `speakability_lint.py` on those files
(already anticipated in `spec-gates.yml` comments) as advisory.

## Out of Scope

- Implementing spec 022’s five Evaluations gates → **022**.
- Gate V device traces → **036**.
- Raising coverage via new product tests → **011** (this spec only re-measures
  and documents).
- Migrating off self-hosted runners → remains **012 #8**; R4 must stay portable
  to any Mac with GA Xcode 26+.
- Xcode Cloud project creation (Account Holder) — allowed as a later substitute
  for R4 steps 3–9; not required to close this spec.
- App Review submission, pricing, territories, DSA → `docs/app-store/`.
- Enabling UITests as a **merge** blocker → only after nightly is green for a
  recorded streak; harvest to a follow-up if still flaky.

## Tasks

- [ ] 1. Keep `docs/CICD_PIPELINE.md` in sync as items land (R1).
- [ ] 2. Workflow concurrency; optional Sonar; LFS pointer gate; CODEOWNERS;
      honest coverage + rollout doc; Dependabot note or `swift` ecosystem (R2).
- [ ] 3. Add `MeetMemento.xctestplan` Online/Device; switch iOS workflows (R2).
- [ ] 4. Nightly: launch UITest, iPad build, Watch build (R3).
- [ ] 5. `release-ios.yml` + `app-store` environment + Checks-API gate + GA
      Xcode assert + archive/export/validate/TF internal + archive assertions
      (R4). Blocked on PLA (00 A1) and a working Distribution identity — land
      the workflow in `workflow_dispatch` dry-run form first.
- [ ] 6. Update branching / branch-protection / CI_RUNNERS docs for release
      env, nightly names, and “never require release/nightly” (R5, R6).
- [ ] 7. Flip `STOREKIT_ENFORCE` policy with a dated comment (R2 / Gate S).

## Verification

- [ ] `bash -n` on new `scripts/ci/*.sh`; workflow YAML parses.
- [ ] PR to `dev`: merge lanes green; nightly/release do not appear as required.
- [ ] Planted LFS pointer (or a fixture) fails the Linux pointer job.
- [ ] `xcodebuild test -testPlan MeetMemento` Online succeeds without a model.
- [ ] Nightly log shows launch UITest ran (or skipped with a named reason).
- [ ] Dry-run `release-ios` on a machine with signing: archive +
      `altool --validate-app` → 0 ITMS. Upload only when Account Holder
      approves the environment.
- [ ] `git ls-files | grep -cE '\.p8$|\.p12$|\.mobileprovision$'` → 0.
- [ ] Coverage comment in `ios-build-online.yml` matches
      `QUALITY_GATE_ROLLOUT.md`.

## Regression Guards

- Spec 025: merge CI must not require on-device FM generation.
- Spec 006: no advisory-as-blocking theater; coverage only ratchets up.
- CONSTITUTION §4 rules 1 (no secrets), 5 (single FM importer), 6 (tests +
  ratchet), 8 (no journal content to Z2), 11–12 (TTS on-device / CoreML
  importer).
- `docs/app-store/07` §4: `notarytool` is never added (iOS App Store upload).
- Frontend preservation: no product UI changes in this spec.
- Do not reintroduce Supabase deploy workflows.
