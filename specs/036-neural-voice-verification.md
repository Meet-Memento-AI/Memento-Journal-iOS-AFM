---
id: 036
title: Neural Voice Verification and Release Gates
tier: P1
status: not-started
effort: 1 session
depends_on: [030, 031, 032, 033, 035]
findings: [zero-egress-artifact-substantiates-the-claim, no-device-ci-exists, masked-and-unmasked-both-gated, xctest-only-no-swift-testing, gate-v-definition]
source_refs: [REQ-TTS-001, REQ-TTS-010, REQ-POS-001, REQ-PERF-009]
tech_refs: [technology/13-neural-tts-coreml.md, technology/11-verification-queue.md]
---

# 036 — Neural Voice Verification and Release Gates

**Traceability:** implements `REQ-TTS-010`. Rolls the measurable claims of specs
`030`–`035` into **Gate V** and pins the public privacy claim to an artifact.
Extends `specs/029-performance-and-speech-excellence.md` R9's gate discipline;
constrained by `specs/014-privacy-model-and-trust-boundary.md` R3's
forbidden-phrase rule and `REQ-POS-001`.

## Why

Every other spec in this family makes a numeric promise. This one is where those
promises either hold on real hardware or the feature does not ship.

It also carries the family's one externally-facing obligation. "Nothing leaves the
device" is the strongest thing this app says about itself, and a voice feature
with a third-party model in it is exactly where a reader would expect that claim
to quietly stop being true. It does not stop being true — but the difference
between a claim and a verified claim is an artifact, and this spec is what
produces one.

There is a discipline here worth stating plainly: **a masked latency number is
not a latency number.** Spec 032's turn-start mask improves what a user feels and
changes nothing about what the system does. Both figures are gated, so a
regression the mask hides is still caught.

## Technology References

- `specs/reference/technology/11-verification-queue.md` — V29, V30, V31, all 🔴
  and all owned by specs in this family.
- `specs/reference/technology/13-neural-tts-coreml.md` §2–§6 — what is ✅ VERIFIED
  from the SDK versus what only a device can answer.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | **There is no device CI.** Every measurement in this family is a human on a phone | Spec 025 replaced `ios-tests.yml` with `ios-build-online.yml` (+ optional `ios-device-eval.yml`); `.github/workflows/spec-gates.yml` gates are source-level only | High — shapes what can be a CI gate |
| 2 | The gate-naming convention is established and must be matched | `.github/workflows/spec-gates.yml:24` `Single FoundationModels importer (spec 017 R1 / P3)`; `:46` `Positioning-claim lint (spec 014 R3 / REQ-POS-001)`; `:54` `Speakability linter selftest (spec 018 R9 / REQ-VOX-006)`; `:64` `Dependency allowlist (spec 021 R6 / REQ-MON-005) [report-only]` | — (convention to follow) |
| 3 | The privacy-claim lint already exists and will police this feature's copy | `scripts/ci/lint_forbidden_phrases.py`; spec 014 R3 forbids "nothing leaves your phone", "no network calls", "airplane mode proves it" and equivalents | High — the obvious marketing line for this feature is a **forbidden phrase** |
| 4 | The repo is **XCTest-only** despite specs naming Swift Testing | `grep -rn 'import Testing' MeetMementoTests MeetMementoUITests` → zero; 47 files `import XCTest` | Medium — write gates in the framework that exists |
| 5 | Latency instrumentation exists and is the right foundation | `MeetMemento/Utils/TurnTimings.swift:22–25`, `MeetMemento/Utils/PerfSignposts.swift:25`; extended by 032 R6 and 029 R1 | — (asset) |
| 6 | **Two** verification items are open and block their owning specs | V29 (ANE, 031) and V30 (roster under AEC, 033). V31 (asset hosting) **withdrawn 2026-08-18** — `DEC-012` bundles the model | High — Gate V cannot close over them |

## Release gates — Gate V

All MUST pass **on physical devices**. A number measured only on a flagship is a
number about a phone almost nobody has yet.

> **Amended 2026-08-18 (`DEC-012`) — download-related gates are withdrawn.** The
> model is bundled, so there is no download to time, no partial state to verify,
> and no proxy capture *during* a download. The zero-egress artifact remains
> required — it is now trivially satisfied, which is the point.
>
> **Amended 2026-08-18 — "oldest supported device" is defined, and it is two
> devices.** This preamble, 031 R5 and 031 R6 all used that phrase and **no spec
> ever defined it**, which left every budget below resting on an unstated
> baseline. Memory and compute have different worst cases, and one device does not
> represent both:
>
> | Floor | Device | Binding for |
> |---|---|---|
> | **Memory floor** | Oldest **Apple Intelligence** device | Peak RSS — the only configuration where 243 MB of weights competes with a resident LLM |
> | **Compute floor** | Oldest supported device (`CapabilityTier.reduced`) | Synthesis RTF, cold-open — slowest ANE, no AFM competing |
>
> Every row below is recorded on **the floor that binds it**, plus the current
> flagship as the ceiling reference. A Reduced-tier device is a first-class target
> because the neural voice ships there (030 R5, amended) — read-aloud needs no
> language model, so the slowest supported hardware will genuinely run this graph.
>
> Neither floor substitutes for the other: a flagship RSS figure says nothing
> about the memory floor, and an Apple-Intelligence-device RTF says nothing about
> the compute floor.

| Gate | Threshold | Source | Kind |
|---|---|---|---|
| Cold open → first playable audio | ≤ 2.5 s (warm-up hidden behind UI) | 031 R3 | Device |
| Warm turn-start, **masked** (perceived) | ≤ 400 ms | 032 R3 | Device |
| Warm turn-start, **unmasked** (instrumented) | ≤ 900 ms | 032 R6 | Device |
| Barge-in time-to-silence | ≤ 150 ms, 20-trial median | 034 R4 | Device |
| TTS bleed into transcript | **0 phrases**, quiet + moderate-noise rooms | 034 R3 | Device |
| Voice switch overhead | < 10 ms, no reload event | 033 R1 | Device |
| Synthesis real-time factor | ≤ 0.25 recorded (target 0.15) | 031 | Device |
| Peak RSS, engine warm + AFM resident | Measured & recorded; escalate above the threshold set at V29 | 031 R6 | Device |
| ANE placement of the main graph | Confirmed and documented | 031 R5 / V29 | Device |
| All shipping voices approved through the AEC path | Sign-off | 033 R7 / V30 / `DEC-009` | Device |
| **Release archive size** | **< 200 MB** — the App Store cellular-prompt threshold | 030 R7 | **CI** |
| Network calls from TTS paths | **0**, proxy-verified | 030 R1 | Device + artifact |
| First-ever synthesis | **Zero CoreML compilation** — shipped artifact is pre-compiled | 030 R2 | Device |
| Bundle completeness | 4 `.mlmodelc` + 3 configs + **exactly 4** style JSONs at bundle root | 030 R2/R4 | CI |

**Gate V does not close while V29 or V30 is open** (CONSTITUTION rule 10). V31 is **withdrawn** — `DEC-012` bundles the model, so there is no hosting question left to answer.

Gates 034 contributes are scoped to that spec's own release, since it is P2 and
off the critical path — the neural voice can ship with rows 4, 5 and 10 pending,
and Gate V is recorded as partial when it does.

## Requirements

**Traceability:** R1 → `REQ-TTS-010` + `REQ-POS-001`; R2 → `REQ-PERF-009`
(debug surface); R3 → `REQ-PERF-009` (regression suite); R4 → CI gate inventory.

**Zone declaration:** `.z0Device` throughout. The proxy capture in R1 exists to
demonstrate exactly that.

### R1. The zero-egress artifact, and the copy it does and does not license (`REQ-TTS-010`)

Every release including the engine archives a **proxy-verified zero-egress
capture**: model load, synthesis, and voice switching exercised on a device
behind a capturing proxy, showing **zero outbound requests** from TTS code paths
(030 R1). The artifact is stored with the release, not merely observed once.

**Public copy for the voice feature MUST NOT exceed what this artifact proves,
and MUST stay inside `REQ-POS-001` and spec 014 R3.** This needs stating because
the natural marketing sentence for this feature — "no third-party AI, nothing
leaves the device" — is **wrong twice**:

1. "Nothing leaves your phone" and its equivalents are **enumerated forbidden
   phrases** in 014 R3, enforced by `scripts/ci/lint_forbidden_phrases.py`, for
   as long as any surface routes to Private Cloud Compute. The voice feature
   being local does not make an absolute app-wide claim true.
2. "No third-party AI" is now imprecise. The engine *is* third-party software; it
   is simply local, license-cleared, and networkless. The honest framing is the
   one `REQ-POS-001` already uses — processing happens on the device — and that
   sentence is fixed text, not a starting point for a variation.

So: the artifact **substantiates the existing claim**. It does not license a new
one. Any voice-specific copy is reviewed against 014 R3 before publication, and
the existing App Store copy gate (`check_asc_metadata.sh`) already enforces the
same rule on store metadata.

**Acceptance (Given/When/Then):**
- Given a release build, when the proxy capture runs across model load,
  synthesis, and voice switching, then zero outbound requests originate from TTS
  code, and the capture is archived with the release.
- Given any new voice-feature copy, when CI runs, then
  `Positioning-claim lint (spec 014 R3 / REQ-POS-001)` passes.
- Given the landing page and store metadata, when audited, then no claim exceeds
  the artifact — specifically, no absolute-privacy phrasing is introduced
  anywhere for this feature.

### R2. `TTSLatencyReport` — internal builds only (`REQ-PERF-009`)

A debug screen, **internal builds only**, renders the 032 R6 logs: a per-turn
waterfall, real-time-factor distribution, and underrun count.

It exists because latency regressions in a voice loop are nearly impossible to
diagnose from a user report — "it felt slow" maps onto at least six stages — and
because the data already exists in `TurnTimings` and the `speech.loop` signposts
and is currently only readable in Instruments.

It renders locally-held data only. No export, no upload, no sharing affordance —
the report contains timing for real conversations, and an export button is how
that leaves the device by accident.

**Acceptance:** given an internal build, when the screen is opened after a
session, then per-turn waterfalls, RTF distribution, and underrun counts render;
given a release build, then the screen does not exist in the binary.

### R3. The regression suite runs before anything audio ships (`REQ-PERF-009`)

The device gates above are scripted and runnable via XCUITest plus instrumentation
hooks, and run **before every release that touches audio, prompts, or the
chunker** — the three inputs that move these numbers.

Written in **XCTest**, matching the repo as it actually is (evidence row 4). A
suite written in a framework the project does not use is a suite that does not
run.

Existing suites stay green: `TTSReadAloudUITests`, `VoiceSettingsUITests`
(updated by 033), `NarrationCoordinatorTests`, `StreamingSentenceChunkerTests`,
`VoicePlaybackServiceTests`, `SpeechTextSanitizerTests`, `SpeakabilityLinterTests`.

**Acceptance:** given a release candidate touching audio, prompts, or the
chunker, when the suite runs on a physical device, then every Gate V row is
exercised and its measurement recorded in this spec.

### R4. CI gate inventory (source-level, the half a machine can check)

Added to `.github/workflows/spec-gates.yml`, following the house naming
convention, each failing with a message naming its `REQ-` id and its spec — never
a generic failure — and each **demonstrated once against a planted violation**:

| Gate name | Owner |
|---|---|
| `TTS zero-egress source scan (spec 030 R1 / REQ-TTS-001)` | 030 |
| `TTS asset manifest integrity (spec 030 R3 / REQ-TTS-002)` | 030 |
| `Phonemizer licensing scan (spec 018 R12 / REQ-TTS-009)` | 018 R12 / 030 |
| `Single CoreML importer (spec 031 R1 / REQ-TTS-004)` | 031 |
| `Expression-tag allowlist (spec 035 R3 / REQ-TTS-008)` | 035 |
| `Dependency allowlist (spec 021 R6 / REQ-MON-005)` | existing — must be **enforcing**, not report-only (030 R7) |
| `Positioning-claim lint (spec 014 R3 / REQ-POS-001)` | existing — now also covers voice copy |
| `Speakability linter selftest (spec 018 R9 / REQ-VOX-006)` | existing — unchanged |

**Acceptance:** every new gate is live, named per convention, and proven to fail
on a planted violation; the dependency allowlist gate is enforcing and green.

## Non-goals

- Implementing the features being verified — specs 030–035.
- Building device CI. These are human-run device measurements, recorded here;
  automating them is its own spec if it is ever worth it.
- Analytics of any kind. Local structured logs only, per the product
  constitution — this spec must not become the place telemetry gets justified
  because "it's for quality."
- Re-litigating thresholds. Each number belongs to its owning spec; this file
  collects and gates them.
- A/B testing voices with users.

## Acceptance

1. Every Gate V row measured on **both** an oldest-supported and a current
   device, with figures written into this spec.
2. Zero-egress proxy capture archived with the release.
3. V29, V30, V31 closed with findings; `DEC-008` and `DEC-009` resolved in
   writing.
4. `TTSLatencyReport` present in internal builds, absent from release builds.
5. All new CI gates live, named per convention, each proven to fail on a planted
   violation.
6. `Positioning-claim lint` green over all voice-feature copy; no absolute-privacy
   phrasing introduced.
7. Full `MeetMementoTests` and `MeetMementoUITests` suites green.

## Regression Guards

- **Spec 014 R3 / `REQ-POS-001`** — the privacy claim is fixed text. An artifact
  proving a strong result is not permission to write a stronger sentence.
- **Spec 029 R1/R2** — instrumented numbers are reported alongside masked ones,
  never replaced by them.
- **CONSTITUTION rule 10** — Gate V does not close over an open 🔴.
- **CONSTITUTION rules 11 and 12** — the fallback path is exercised by the suite,
  not just the neural path; the airplane-mode case is a gate, not an afterthought.
- **Product constitution** — no analytics egress from any measurement here.

## Open question for the owner

**Does the neural voice ship default-on, or behind a first-run choice?** Specs
030–035 are written **default-on**, with the asset download beginning at first
launch and the `AVSpeechSynthesizer` fallback covering the gap. That is the right
default if the bundle is modest.

If 030 R7's measurement comes back near or above 250 MB, the question becomes
real: every user pays that download on day one for a feature many will never
knowingly use. The alternative — surface the neural voice as an opt-in the first
time a user opens Narration Mode or the voice picker — costs a discovery moment
and saves the bandwidth, and it changes 030 R5's degradation UX and 033 R3's
migration default.

Not a blocker for authoring or for early implementation. It **is** a blocker for
release, and the measured size is what should decide it rather than a preference
stated in advance.
