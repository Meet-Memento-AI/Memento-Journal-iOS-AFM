---
id: 051
title: On-Device Model Tier — AFM 3 Core Advanced by Default Where the Hardware Allows
tier: P1
status: draft (2026-09-25 — plan only; R0 needs a Mac with Xcode 27)
effort: 2–3 sessions, stacked commits (see Tasks)
depends_on: [017, 022, 029, 043]
findings:
  - every-session-uses-the-implicit-default-model
  - provenance-cannot-tell-core-from-core-advanced
  - latency-clamps-tuned-for-a-3b-model
  - no-sdk-verification-of-a-tier-selector
  - device-eval-lane-has-no-12gb-device
source_refs: [REQ-INT-001, REQ-INT-003, REQ-INT-009, REQ-PRM-004, REQ-PRIV-001]
tech_refs: [technology/01-foundation-models.md, technology/04-evaluations.md, technology/11-verification-queue.md]
---

# 051 — On-Device Model Tier

**Traceability:** extends spec [`017`](017-intelligence-boundary-and-prompt-architecture.md)
(single importer, routing table, runtime-derived context budget) with a
second on-device axis: *which* on-device model. Latency budgets stay
[`029`](029-performance-and-speech-excellence.md) Amendment A's; this spec
only adds a second set for the larger model. Provenance joins spec
[`043`](043-eval-run-warehouse.md)'s `(prompt_version, model_identifier)`
index. Privacy stays [`014`](014-privacy-model-and-trust-boundary.md):
both models are Z0, nothing in this spec moves content off the device.
This spec mints the **`REQ-TIER-`** series inline.

**Does not implement:** Private Cloud Compute (Z1), bundling our own weights
through `CoreAILanguageModel` or `MLXLanguageModel`, a user-facing model
picker, larger `EntryRetriever.maxEntries`, re-enabling tool calls during
guided decoding, or retiring any 3B-motivated guard (`TurnClassifier`,
`ReplyRenderer` markers). Each of those is either a product decision or a
follow-up gated on this spec's measurements.

## Why

Apple's third-generation foundation models ship two on-device models
([Apple ML Research](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)):

| Model | Size | Runs on |
|---|---|---|
| AFM 3 Core | 3B, dense | every Apple Intelligence device on iOS 27 |
| AFM 3 Core Advanced | 20B, sparse (1–4B active per request; weights in NAND, experts paged per prompt) | ≥ 12 GB unified memory: iPhone Air, iPhone 17 Pro / Pro Max, iPad M4+, Mac M3+, Vision Pro M5 |

An Apple engineer on the developer forums
([thread 832910](https://developer.apple.com/forums/thread/832910)) says the
most capable devices run Core Advanced and all other devices run Core, and
that model details and guidance would evolve during the beta. Public docs
describe no developer-facing tier parameter on `SystemLanguageModel`; the
OS resolves `SystemLanguageModel.default` to the device's model.

The product goal: **every person whose device can run Core Advanced gets
it; everyone else gets Core, and only then.** The goal is mostly already met
by accident: every Memento session goes through the implicit default model.
The problem is that nothing in Memento *knows* which model answered, and
every budget was tuned for the smaller one, so the larger model is both
invisible to evaluation and capped at the smaller model's envelope.

## Current State (evidence)

> Verified 2026-09-25 against `main` @ `c43e572`. Line numbers rot —
> re-verify before editing.

| # | Finding | Evidence | Severity |
|---|---------|----------|----------|
| 1 | **Every session uses the implicit default model.** Seven construction sites call `LanguageModelSession(instructions:)` / `(transcript:)` with no `model:`; availability, `contextSize`, and `tokenCount` read `SystemLanguageModel.default`. There is no single place to choose a model. | `FoundationModelsIntelligenceService.swift` `makeSession` :585, `estimateProfile` :1963, `summarizeConversation` :2054, `reflect` :2492, `weeklyReflection` :2551, `refreshProfile` :2628, `evalRawGenerate` :2744; `availability()` :647; `currentWindow()` :714; `measurePromptTokens` :773 | High |
| 2 | **Provenance cannot tell the two models apart.** `modelIdentifier(for: .z0Device)` returns `"apple.system.on-device"` for both. That string is persisted on `ExperienceProfile`, `AnswerFeedback`, chat turns, and flows into `eval.generation` and `answer_feedback`, both indexed on `(prompt_version, model_identifier)`. Any quality delta between models is averaged away. | `FoundationModelsIntelligenceService.swift:2458-2464`; `supabase/migrations/20260827064226_eval_generations.sql:100`; `…20260825030311_answer_feedback.sql:83` | **Critical** |
| 3 | **The per-turn perf line carries zone, not model.** `logOutcome` logs `ran=z0.device`; spec 029's latency numbers cannot be split by model. | `FoundationModelsIntelligenceService.swift:723-748` | High |
| 4 | **Latency clamps were tuned on the 3B model.** Evidence is capped at 3,500 chars and history at 2,000 regardless of window; retrieval is capped at 5 entries × 500 chars. Correct for Core; unmeasured for Core Advanced, whose prefill profile differs (per-prompt expert paging from NAND). | `Prompt/ContextBudget.swift:105-106`; `Retrieval/EntryRetriever.swift:179-183` | Medium |
| 5 | **The target builds against Xcode 27 with an iOS 26.0 floor.** So three model generations are live at once: pre-AFM 3 (iOS 26.x), AFM 3 Core, and AFM 3 Core Advanced (iOS 27). | `project.pbxproj` `IPHONEOS_DEPLOYMENT_TARGET = 26.0`; `.github/workflows/ios-build-online.yml:30` (`xcode-27`) | Medium |
| 6 | **Whether the SDK exposes the tier is unverified.** `technology/01` §3 was verified against 27A5228h (beta 4) and records no tier API; the forum post predates GM. No lane in this repo can read the GM `FoundationModels.swiftinterface`. | `specs/reference/technology/01-foundation-models.md` §3, §8 | High |
| 7 | **The device-eval lane runs a simulator, not a 12 GB phone.** The simulator uses the host Mac's model, so eval runs cannot currently be attributed to either phone tier. | `.github/workflows/ios-device-eval.yml:24, 57` | Medium |
| 8 | **Several guards exist *because* of the 3B model** and are correct to keep on Core: deterministic `TurnClassifier`, `{{quote:n}}` markers, no tools during guided decode. | `Routing/TurnClassifier.swift:6`; spec 050 R2; `makeSession` :576-582 | Low (keep) |

## Architecture

### Today

```
every call site ──► LanguageModelSession(instructions:)   (implicit default)
                       └─ OS picks: Core Advanced on ≥12 GB, Core elsewhere
modelIdentifier ──► "apple.system.on-device"              (both models)
ContextBudget   ──► one clamp set                          (tuned on 3B)
```

### Target

```
                 ┌─────────────────────────────────────┐
 availability ──►│ OnDeviceModelTierResolver (pure)     │──► OnDeviceModelTier + source
 os version   ──►│  inputs: sdkReportedTier?,           │     (.reported | .inferred)
 memory bytes ──►│  availability, osMajor, memoryBytes  │
                 └─────────────────────────────────────┘
                                   │
     ┌─────────────────────────────┼───────────────────────────────┐
     ▼                             ▼                               ▼
 onDeviceModel()             modelIdentifier(zone, tier)      ContextBudget(window:, tier:)
 (the ONE construction       "apple.system.on-device          Core clamps unchanged;
  site; explicit selection    .afm3-core-advanced"            Core Advanced clamps from
  if R0 finds an API)                                         measured TTFT (R5)
```

`OnDeviceModelTier` and its resolver are pure Swift (no `FoundationModels`
import), so they are unit-testable off device and on the Linux toolchain,
like `ModelRouter`. Only the SDK read, if R0 finds one, lives in the single
importer.

## Requirements

### R0. Verify the SDK surface before writing selection code (`REQ-TIER-000`)

On a Mac with the Xcode 27 GM, search
`FoundationModels.swiftinterface` for any member that names or selects an
on-device model tier (e.g. `variant`, `tier`, `capabilit`, `advanced`, new
`SystemLanguageModel` statics or initializers, new `UseCase` cases), and for
any `Availability.UnavailableReason` case specific to the larger model.
Record the result in `technology/01` §3 and as a new verification-queue
item beside V28.

The result picks one of two paths. Everything else in this spec is the same
on both.

- **Path A — the SDK exposes the tier.** Memento asks for Core Advanced
  explicitly when it is available and falls back to Core otherwise (R2).
  The resolver's `source` is `.reported`.
- **Path B — the OS chooses and says nothing.** Memento keeps the implicit
  default (the OS already does the fallback), and the resolver infers the
  tier from hardware (R1). The resolver's `source` is `.inferred`.

**Acceptance:** `technology/01` §3 states which path applies, with the SDK
build number and the exact declarations found (or "not found").

### R1. One pure tier value, resolved once (`REQ-TIER-001`)

Add `Services/Intelligence/OnDeviceModelTier.swift`, Foundation-only:

```swift
enum OnDeviceModelTier: String, Sendable, Equatable {
    case preAFM3          // iOS < 27: the 2025-generation model
    case afm3Core
    case afm3CoreAdvanced
    case unknown          // model unavailable, or no signal
}

enum OnDeviceModelTierSource: String, Sendable, Equatable {
    case reported         // read from the SDK (path A)
    case inferred         // derived from OS + memory (path B)
}

struct OnDeviceModelTierResolver {
    static func resolve(
        reported: OnDeviceModelTier?,
        modelAvailable: Bool,
        osMajorVersion: Int,
        physicalMemoryBytes: UInt64
    ) -> (tier: OnDeviceModelTier, source: OnDeviceModelTierSource)
}
```

Rules, in order:

1. Model unavailable → `.unknown`.
2. A reported tier wins → that tier, `.reported`.
3. `osMajorVersion < 27` → `.preAFM3`, `.inferred`.
4. Physical memory at or above the Core Advanced floor → `.afm3CoreAdvanced`,
   `.inferred`; otherwise `.afm3Core`, `.inferred`.

The memory floor sits between Apple's 8 GB and 12 GB classes, because a
12 GB device reports somewhat less than 12 GiB of physical memory. Write it
as a decimal byte count (e.g. `10_000_000_000`) with a comment saying it is a
hardware class boundary, not a context window. Do not spell it as a
`* 1024` product: `check_no_hardcoded_context_budgets.sh` rejects that shape
on purpose.

The importer calls the resolver once per process after the first
`.available` result, with `ProcessInfo.processInfo.physicalMemory` and
`ProcessInfo.processInfo.operatingSystemVersion.majorVersion`, and caches it
beside `cachedAvailability`. It follows the same rule: cache only a positive
result, so a device whose Core Advanced assets are still downloading
re-resolves later instead of pinning Core for the process.

**Acceptance:** `OnDeviceModelTierTests` covers each rule, the 8 GB / 12 GB
boundary on both sides, and "reported beats inferred". Both
`check_single_intelligence_importer.sh` (still 1) and
`check_no_hardcoded_context_budgets.sh` pass.

### R2. One construction site for the on-device model (`REQ-TIER-002`)

Add `private func onDeviceModel() -> SystemLanguageModel` to the importer
and change all seven session sites (finding 1) to
`LanguageModelSession(model: onDeviceModel(), …)`. Route
`availability()`, `currentWindow()`, and `measurePromptTokens` through the
same instance so the window and token counts come from the model that will
actually run.

- **Path B:** `onDeviceModel()` returns `SystemLanguageModel.default`. This
  is a pure refactor with no behaviour change. It exists so that if Apple
  ships a selector later, adopting it touches one function.
- **Path A:** `onDeviceModel()` returns the Core Advanced model when its
  availability is `.available`, else the Core model. If a Core Advanced call
  throws `SystemLanguageModel.Error` (assets unavailable), that turn retries
  once on Core, and the process drops its cached tier so the next turn
  re-resolves. A retry happens at most once per turn and runs under the same
  `ModelRuntimeGate` hold. It never overlaps the failed call.

The speculative pool's fingerprints gain the tier, so a session prewarmed
for one model is never adopted for the other.

**Acceptance:** no `LanguageModelSession(` call in the importer omits
`model:`, enforced by an extension to `check_single_intelligence_importer.sh`
(or a sibling script). On path A, a unit test over a fake availability seam
proves: Core Advanced available → Core Advanced; unavailable, not ready, or
throwing → Core; neither available → the existing `.unavailable` path.

### R3. Provenance names the model (`REQ-TIER-003`)

`modelIdentifier(for:)` becomes `modelIdentifier(for:tier:)`. For `.z0Device`:

| Tier | Identifier |
|---|---|
| `.afm3CoreAdvanced` | `apple.system.on-device.afm3-core-advanced` |
| `.afm3Core` | `apple.system.on-device.afm3-core` |
| `.preAFM3` | `apple.system.on-device.pre-afm3` |
| `.unknown` | `apple.system.on-device` (unchanged) |

This is additive: historical rows keep the bare string, and a
`like 'apple.system.on-device%'` join still finds everything on-device.
Z1 and `"swift"` identifiers are untouched. Inferred tiers are not marked in
the identifier. The source goes on the perf line (R4) and in the convo-sim
row, because the identifier is a wire format (`TrustZone.identifier`'s rule)
and should not fork on how the tier was learned.

**Acceptance:** `ChatContinuityTests` keeps its bare-string round-trip case
and adds a suffixed one. A new test pins all four strings.
`ConversationSimulation` writes `model_tier` and `model_tier_source`
columns beside `model_identifier`.

### R4. The perf line names the model (`REQ-TIER-004`)

`logOutcome` gains `tier=<rawValue> tier_source=<rawValue>`. Both are
content-free enum strings, so CONSTITUTION §4 rule 3 holds. `DiagLatencyProfile`
and `AskTurnPerf` carry the tier so spec 029's numbers split by model.

**Acceptance:** the log format test (or a new one) asserts both fields and
asserts that no question or reply text appears.

### R5. Tier-aware latency clamps, measured first (`REQ-TIER-005`)

`ContextBudget.init(window:)` gains a `tier:` parameter (default `.unknown`
so existing call sites and tests keep today's numbers). Core, pre-AFM 3, and
unknown use today's clamps unchanged. Core Advanced gets its own
`maxEvidenceLatencyChars` / `maxHistoryLatencyChars` pair. Those are the
**only** new constants, and they stay prefill-latency budgets, not windows.

The Core Advanced values start **equal** to Core's. They change only when a
device run (Verification, below) shows Core Advanced's p50 time-to-first-token
at the larger budget is within spec 029's target on an iPhone 17 Pro. Record
the before/after numbers in this spec's Verification section in the same
commit that changes them.

`EntryRetriever.maxEntries` stays 5 in this spec (050 regression guard).

**Acceptance:** `ContextBudgetTests` proves Core, pre-AFM 3, and unknown are
byte-identical to today for every window it already covers, and that Core
Advanced never exceeds its own clamp.

### R6. Evaluation segments by model (`REQ-TIER-006`)

- The eval warehouse import (`scripts/eval/import_run.sh`) passes
  `model_tier` through. No migration is needed: `model_identifier` already
  carries it (R3).
- Spec 022's study reports every quality metric twice, once per tier. A
  delta between tiers is a finding, not noise.
- The device-eval lane gains a documented physical-device option with one
  12 GB phone (iPhone 17 Pro or Air) and one 8 GB phone. Simulator runs
  are labelled with whatever the resolver reports on the host Mac and are
  never compared across tiers.

**Acceptance:** `docs/CI_RUNNERS.md` lists the two device classes. One
convo-sim run per tier lands in the warehouse before R5's clamps move.

## Out of Scope

- A user-visible "Advanced model" label or setting. If wanted later, it reads
  `OnDeviceModelTier` and needs its own copy review against REQ-POS-001.
- Retiring 3B-motivated guards on Core Advanced. Each one needs a per-tier
  eval delta first (Follow-ups).
- PCC, third-party providers, `CoreAILanguageModel`, MLX. Apple's weights
  are not redistributable, a self-bundled 20B model means a 10+ GB download
  and jetsam risk on phones, and `technology/01` §8 requires an explicit
  product decision before leaving the system model.
- Core Advanced's multimodal input for photo attachments.

## Tasks

- [ ] 0. `spec(051)`: this plan.
- [ ] 1. `R0` (Mac): read the Xcode 27 GM interface; update `technology/01`
      §3 and the verification queue; pick path A or B in this spec.
- [ ] 2. `tier`: `OnDeviceModelTier` + resolver + `OnDeviceModelTierTests`.
      Pure Swift; compiles on the Linux toolchain like spec 050's units. (R1)
- [ ] 3. `model-site`: `onDeviceModel()`; all seven sites pass `model:`;
      availability / window / token count use it; pool fingerprint gains the
      tier; importer-script check. Path A adds selection and a single retry. (R2)
- [ ] 4. `provenance`: `modelIdentifier(for:tier:)`; perf line; `AskTurnPerf`;
      convo-sim columns; `ChatContinuityTests` + identifier test. (R3, R4)
- [ ] 5. `budget`: `ContextBudget(window:tier:)` with Core Advanced clamps
      equal to Core's; `ContextBudgetTests`. (R5)
- [ ] 6. `eval`: import script passthrough; `docs/CI_RUNNERS.md` device classes;
      one warehoused run per tier. (R6)
- [ ] 7. `budget (measured)`: move Core Advanced clamps only if step 6's
      numbers clear spec 029's target; record them here. (R5)

Steps 2, 4, and 5 do not depend on R0 and can land first. Step 3 on path B is
a no-op refactor and can also land before R0; path A's selection lands
after it.

## Verification

- [ ] `xcodebuild test -scheme withMemento -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
      -only-testing:withMementoTests/OnDeviceModelTierTests
      -only-testing:withMementoTests/ContextBudgetTests
      -only-testing:withMementoTests/ChatContinuityTests
      -only-testing:withMementoTests/ModelRouterTests
      -only-testing:withMementoTests/ModelRuntimeGateTests` green.
- [ ] Full online suite per `.github/PULL_REQUEST_TEMPLATE.md`.
- [ ] `scripts/ci/check_single_intelligence_importer.sh` reports exactly 1.
- [ ] `scripts/ci/check_no_hardcoded_context_budgets.sh` passes.
- [ ] Device, iPhone 17 Pro, iOS 27: the perf line shows
      `tier=afm3CoreAdvanced`; the Xcode Foundation Models instrument's
      TTFT and tokens/sec are recorded for Ask (light and notebook), entry
      reflection, and weekly reflection, and compared against V28's floor.
- [ ] Device, an 8 GB iPhone, iOS 27: the perf line shows `tier=afm3Core`,
      and budgets are byte-identical to `main`.
- [ ] Device, iOS 26.x: `tier=preAFM3`.
- [ ] Narration on the 12 GB phone with neural TTS loaded: no memory
      warning or jetsam across a 20-turn conversation (Risks).

## Risks

| Risk | Mitigation |
|------|------------|
| Apple ships no tier API, and the memory heuristic mislabels a device (e.g. a future 12 GB device Apple excludes, or a Mac/iPad class boundary) | The label is provenance only, and `source=inferred` is always logged. Selection stays with the OS on path B, so a wrong label never runs the wrong model. It only mislabels a row, which a reported tier later corrects. |
| Core Advanced is slower to first token (paging experts from NAND per prompt), and the speculative pool prewarms five recipes | Clamps start equal to Core's (R5). The perf line splits by tier (R4). Prewarm fingerprints include the tier (R2). If Ask light regresses, a later amendment may add a per-intent tier column to `ModelRouter`'s table rather than a scattered conditional (spec 017 R2). |
| Crash workarounds (`ModelRuntimeGate` serialization; no tools during guided decode) were observed on the old runtime and may not hold on Core Advanced | Both stay in force on every tier. Re-verify on device before relaxing either, in a separate spec. |
| Memory pressure from Core Advanced plus neural TTS (CoreML) during narration on 12 GB phones | Verification step above. The OS manages model memory; if jetsam appears, narration defers TTS model load, not the model tier. |
| A device-class suffix in `model_identifier` reaches `answer_feedback` when a person reports or opts in to feedback | It is a coarse hardware class, sent only on the existing user-initiated paths. Check `docs/app-store/03-privacy-labels-and-manifest.md` before step 4 merges; if it needs a label change, strip the suffix from the feedback payload only and keep it in local and eval provenance. |
| Path A's retry masks a persistent Core Advanced fault | At most one retry per turn; the cached tier is dropped so the next turn re-resolves; the retry logs `tier_fallback=1` for the warehouse. |

## Follow-ups (not this spec)

- Per-tier prompt variants: a richer `ask-core` for Core Advanced, only after
  a per-tier eval delta justifies the maintenance cost.
- Relax `TurnClassifier` or quote markers on Core Advanced if per-tier evals
  show the model does the job itself.
- Raise `EntryRetriever.maxEntries` for Core Advanced (needs 044 retrieval
  measurements, not just latency).
- Core Advanced multimodal photo understanding for attachments.

## Regression Guards

- **`REQ-INT-001` / CONSTITUTION §4 rule 5**: the tier type and resolver are
  pure Swift, and the importer count stays 1.
- **`REQ-INT-009` / spec 017 R9**: no window literal is introduced; the
  memory floor is a hardware class boundary written as a decimal byte count;
  the window is still read from the model that runs.
- **CONSTITUTION §4 rule 3**: the perf line adds enum strings only.
- **Spec 017 R2**: `ModelRouter`'s table is untouched. Tier is not a zone.
- **Spec 029 Amendment A**: Core's clamps are byte-identical to today.
- **Spec 050**: `maxEntries` stays 5; markers and the renderer run on every tier.
- **Graceful degradation**: a device with no Apple Intelligence still takes
  the existing `.unavailable` path, and `availability()` still caches only
  positive results.
