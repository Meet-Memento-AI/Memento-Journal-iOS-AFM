---
id: 031
title: Neural Synthesis Engine Core
tier: P1
status: in-progress (2026-08-19) — Engine shipping; DEC-008 locked to `.cpuAndNeuralEngine` (GPU excluded); V29 device traces still to archive
effort: 2 sessions
depends_on: [030]
findings: [coreml-import-containment, first-load-is-compilation-not-inference, engine-seam-is-avfoundation-typed, playback-completion-callback-type, sample-rate-conversion-boundary, memory-pressure-release-valve]
source_refs: [REQ-TTS-001, REQ-TTS-003, REQ-TTS-004, DEC-008, DEC-012]
tech_refs: [technology/13-neural-tts-coreml.md, technology/06-speech-and-audio.md]
---

# 031 — Neural Synthesis Engine Core

**Traceability:** implements `REQ-TTS-004` on the verified asset root produced by
`specs/030-neural-tts-model-assets.md`. Owns `DEC-008` and V29. Constrained by
`specs/028-conversational-narration.md` R3's session-ordering machinery, which it
must subsume rather than replace, and by CONSTITUTION rules 11 and 12
(2026-08-18).

## Why

This is the only module that touches CoreML, and that containment is the point.
The model is third-party, its ANE placement is unmeasured, and a future iOS
release could break it — so the engine is built as a component that can be
swapped, bucketed, or turned off entirely without any caller noticing. It hides
behind the utterance-session primitives the app already speaks through
(`beginUtteranceSession` / `enqueue` / `finishEnqueueing`), which means the
fallback path (`030` R5) costs nothing extra: it is the same call sites, routed
differently.

The second reason for this spec's shape: **the dominant avoidable latency is
model load, not inference.** A first-ever load compiles the graph for its target
compute unit and takes seconds. Everything users will describe as "the voice is
slow" traces back to when that load happened — which is why warm-up is tied to
intent, and why a play button must never be the thing that triggers a first load.

## Technology References

- `specs/reference/technology/13-neural-tts-coreml.md` §2 (`MLComputeUnits`,
  `MLOptimizationHints` — **✅ VERIFIED**, iOS 27.0 SDK 27A5228h), §3 (the ANE
  question — 🔴, V29), §4 (`AVAudioPlayerNode.scheduleBuffer` and completion
  callback types — **✅ VERIFIED**), §5 (sample-rate risk — 🔴).
- `specs/reference/technology/06-speech-and-audio.md` §B1 (amended) — why the
  complete-text constraint does not reach this engine.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | The existing "engine seam" is not an engine seam — it is typed on AVFoundation and can only ever hold an `AVSpeechSynthesizer` | `MeetMemento/Services/VoicePlaybackService.swift:22` `protocol SpeechSynthesizing` declares `speak(_ utterance: AVSpeechUtterance)`, `stopSpeaking(at: AVSpeechBoundary)`, `synthesizerDelegate: AVSpeechSynthesizerDelegate?` | High — a second engine cannot be injected here without a new boundary |
| 2 | There is **no audio output graph at all** — no `AVAudioPlayerNode`, no engine output chain. `AVAudioEngine` exists only on the capture side | `grep -rn 'AVAudioPlayerNode' MeetMemento/` → zero hits; `MeetMemento/Services/SpeechService.swift` owns the only `AVAudioEngine` (input tap) | High — greenfield playback path |
| 3 | Warm-up today is a zero-volume utterance — a trick that has no analogue for a model that must be compiled and loaded | `VoicePlaybackService.swift:434` `warmSynthesizer()` speaks `" "` at zero volume | Medium — concept survives, mechanism does not |
| 4 | The session-ordering machinery that makes turn two work is subtle and was expensive to get right | `VoicePlaybackService.swift:648` `waitForSessionRelease()`; `shouldReleaseAudioSession(...)` pure guard; `sessionGeneration` counters; utterances buffered until activation lands (`:271` `enqueue`) — all per spec 028 R3 | **Critical** — subsume, never bypass (CONSTITUTION §2) |
| 5 | Callers speak through three primitives and know nothing about the engine — the property that makes this whole family cheap | `VoicePlaybackService.swift:243/:271/:297`; callers: `NarrationCoordinator.consumeReplyProgress`, `toggleSpeech`, `speakPreview` | — (asset to protect) |
| 6 | No CoreML anywhere; nothing establishes where model code is allowed to live | `grep -rn 'import CoreML' MeetMemento/` → zero hits (2026-08-18) | Medium — rule 11 exists to answer this before the first import |

## Requirements

**Traceability:** R1 → `REQ-TTS-004` and CONSTITUTION rule 11; R2 → `REQ-TTS-004`;
R3 → `REQ-TTS-004` (warm-up); R4 → `REQ-TTS-006` (switching is free — catalog is
033's); R5 → `DEC-008` / V29; R6 → `REQ-TTS-004` (memory); R7 → `REQ-TTS-004`
(cancellation, load-bearing for 034's barge-in); R8 → `REQ-TTS-003`; R9 has no
`REQ-` ID — derived testability requirement.

**Zone declaration:** `.z0Device`. Synthesis is a local computation over local
text; no network, no IPC to anything outside the app, per `REQ-TTS-001` and
CONSTITUTION rule 12.

### R1. One importer, one actor, one instance (`REQ-TTS-004`)

`SupertonicEngine` is an `actor`, with exactly one instance app-wide, owning all
CoreML model objects and the tokenizer. **It is the only Swift module in the app
permitted to `import CoreML`** — the same containment rule as `FoundationModels`
(CONSTITUTION rule 5), enforced the same way, for a sharper reason: this is a
third-party model in a permanently-shipping product, so the day it needs
replacing is a question of when, not whether.

Sibling files carry the explicit "no `import CoreML`" comment convention already
used around `FoundationModelsIntelligenceService`
(`PromptRegistry.swift`, `TurnClassifier.swift`, `EmbeddingService.swift` all do
this today) so the rule is visible where it would be violated.

**CI gate:** `Single CoreML importer (spec 031 R1 / REQ-TTS-004)` — modelled on
the shipped `Single FoundationModels importer` gate, failing with a message
naming `REQ-TTS-004` and this spec, proven against a planted violation.

**Acceptance:** given any branch adding `import CoreML` to a second file, when CI
runs, then the build fails naming `REQ-TTS-004`.

### R2. The engine boundary — callers cannot tell which synthesizer is serving

Two modules, one contract:

- **`SupertonicEngine`** (actor) — text + style in, `AVAudioPCMBuffer` out. It
  owns models and tokenizer and nothing else. It does not touch `AVAudioSession`,
  does not schedule playback, and does not know what a message id is.
- **`TTSPlayback`** — an `AVAudioEngine` + `AVAudioPlayerNode` graph that
  schedules buffers, exposing `enqueue(_:)`, `flushAndStop()`, and a completion
  stream.

The existing utterance-session primitives route to `SupertonicEngine + TTSPlayback`
when assets are ready **and** the selected voice is a neural style; otherwise to
`AVSpeechSynthesizer`. Callers are unchanged. `SpeechTextSanitizer` stays where it
is — inside `enqueue`, one choke point, applying to both engines
(`VoicePlaybackService.swift:271`).

**A new engine-level seam is required.** The existing `SpeechSynthesizing`
protocol (`:22`) is typed on `AVSpeechUtterance`/`AVSpeechBoundary` and is a
*test* seam, not an engine abstraction. Do not widen it into a false abstraction
over two unlike engines; introduce a narrow protocol above it that both paths
satisfy, and leave `SpeechSynthesizing` doing the job it already does well.

**Buffer format:** `synthesize(text:style:language:)` returns the model's native
mono Float32 PCM. **No intermediate files.** Format conversion is R-scoped: none
on the read-back path; on the conversation path a conversion stage is unavoidable
(R5 of spec 034, and `technology/13` §5 — voice-processing I/O commonly
negotiates a different rate). Any claim of "no conversions anywhere" is false on
the conversation path and must not be written into code comments as if it were a
guarantee.

**Playback completion uses `AVAudioPlayerNodeCompletionDataPlayedBack`** — ✅
VERIFIED enum, `technology/13` §4. `DataConsumed` fires when the node *takes* the
buffer, not when the user has *heard* it. Since narration re-arms the mic on
drain (028 R1.5), using `DataConsumed` would open the mic while audio is still
sounding — precisely the class of ordering defect 028 R3 exists to prevent, in a
new disguise.

**Acceptance (Given/When/Then):**
- Given the neural path active, when read-aloud and Narration Mode run, then no
  call site outside `VoicePlaybackService` changed — asserted by diff review and
  by the existing `NarrationCoordinatorTests` mocks continuing to compile
  unmodified.
- Given a queue drain, when the mic re-arms, then the last buffer has finished
  **playing back**, not merely been consumed — asserted by the completion-callback
  type in code and by 028's four-turn device run.
- Given markdown-bearing chat prose, when spoken on either engine, then it passes
  through `SpeechTextSanitizer` exactly once.

### R3. Warm-up follows intent, never the play button (`REQ-TTS-004`)

`prepare()` loads the graphs and runs one throwaway synthesis (~5 words) off the
main thread. It is **idempotent** and MUST be a no-op when already warm.

It is invoked when a journal session or conversation view **appears** — the
moment a user signals they may speak or listen. It MUST NOT be invoked by the
play action, because first-load compilation takes seconds and that cost, spent at
the moment of a tap, is the entire difference between "instant" and "broken".
The app already has the right hook shape: `ChatService.prewarm()` warms the voice
catalog today, and `AIChatView.startNarration()` warms before starting.

> **Amended 2026-08-18 (`DEC-012`).** The engine loads **pre-compiled
> `.mlmodelc`** directories from the app bundle, by **bare filename** — synchronized
> groups flatten resources to the bundle root, so there is no `Voices/` path at
> runtime (030 R2). Two consequences for this requirement: **no CoreML
> compilation happens at runtime at all**, which removes the multi-second
> first-load cost warm-up was partly there to hide; and warm-up is still required,
> because ANE specialization on first load remains. Warm-up got cheaper, not
> unnecessary.

`MLModelConfiguration.optimizationHints` is **not** set until `DEC-008` resolves
(R5): with dynamic shapes the default `.frequent` reshape hint is correct; with
buckets, `.infrequent` is. Setting it early against a guess produces a
plausible-looking wrong answer.

**Acceptance (Given/When/Then):**
- Given a warm engine, when `prepare()` is called again, then it returns in
  **< 5 ms** and performs no load.
- Given a cold app, when the Chat page appears, then warm-up starts without
  blocking the UI and the composer remains interactive within spec 029 R2's
  400 ms budget.
- Given a cold engine, when the user taps play, then the play action never
  performs a first load — asserted by instrumentation showing load began at view
  appearance.

### R4. Voice switching is a parameter change, not a reload (`REQ-TTS-006`)

One loaded model serves every voice; the style vector is a per-call input.
Switching MUST NOT reload, recompile, or re-warm anything, and MUST NOT be
reported as a load event. Spec 033 A1 verifies the user-visible half (< 10 ms,
no reload logged); this requirement is the engine-side guarantee that makes it
achievable.

**Acceptance:** given a warm engine, when the style changes between two
consecutive `synthesize` calls, then zero model-load or compile events are
emitted — asserted by a counter in the engine, not by wall-clock timing alone.

### R5. Compute placement is measured, then documented (`DEC-008`, V29)

Request `.cpuAndNeuralEngine`. **`.all` is withdrawn — it does not work on
device** (see the 2026-08-18 finding below). A compute-unit request is in any case
a request, not a guarantee — Core ML segments the graph and places each segment
where it judges best, so ANE residency is an outcome to be verified, never declared.

Actual placement MUST be recorded via Xcode's Core ML performance report **on a
physical device** at integration time, and the result documented in the PR and in
`technology/13` §3.

> **Scope corrected 2026-08-18 by compiling the bundle.** The graph at risk is
> **`VectorEstimator`** (the flow-matching estimator, 243 MB of 331 MB, run
> iteratively) and secondarily `Vocoder` — not "text_to_latent", which does not
> exist in the export. Both are dynamic on **one bounded axis**
> (`RangeDims` 17…512 and 4…512 respectively); `TextEncoder` and
> `DurationPredictor` are **fully fixed**. If `VectorEstimator` is not
> ANE-resident, **`DEC-008` activates** — but as **enumerated shapes** over that
> single bounded axis, not as three duplicated graphs. The earlier ~730 MB
> worst case assumed graph triplication and is withdrawn.

> **`.all` is unusable — measured on device 2026-08-18 (iPhone 16 Pro, iOS 26).**
> Under `MLComputeUnits.all` Core ML dispatches `Vocoder` to the **GPU via
> MPSGraph**, which requires static shapes and cannot accept that graph's dynamic
> `RangeDim` latent axis. Prediction fails at load-of-shape time:
>
> ```
> Vocoder.mlmodelc/model.mil:242:12: error: invalid axis: -1258641855,
>   axis must be in range -|rank| <= axis < |rank|
> 'mps.expand_dims' op invalid axis: … rank = 4
> MPSRuntime.mm:1515: error 'shape for TensorData is not static'
> ```
>
> The axis value is uninitialized memory, not a computed index. **Resolution:
> exclude the GPU** — `SupertonicCompute.cpuAndNeuralEngine`. This does **not**
> activate `DEC-008`: enumerated shapes were the contingency for the *ANE*
> rejecting the dynamic axis, and the ANE path is not what failed. `DEC-008`
> remains open pending the Core ML performance report.
>
> User-visible symptom, worth recording because it cost hours: prediction threw,
> the caller's `catch` substituted `AVSpeechSynthesizer`, and the bug presented as
> **"the system voice is playing"** rather than as an error. A fallback that
> silently swaps voices hides exactly the failure it is meant to cover — hence
> spec 036's requirement that bring-up surface engine errors instead.
>
> Post-fix, measured on device: all six `SupertonicEngineDeviceTests` pass, four
> voices render and differ, and **RTF = 0.254** (1.162 s wall for 4.568 s of
> audio) with zero MPS errors in the log.

Per CONSTITUTION rule 10, **no engine code is written against the ANE assumption
until V29 closes.** This is the requirement most likely to reorder the family, and
it is cheap to answer — a half-day with a scratch project and a device.

**Acceptance (Given/When/Then):**
- Given the FP16 bundle on a physical device, when the Core ML performance report
  runs, then per-layer placement is recorded in V29 and `technology/13` §3.
- Given a negative result, when work continues, then `DEC-008`'s bucketing is
  specified in this file with measured bucket boundaries before implementation
  proceeds — not assumed.

### R6. Memory pressure has a release valve (`REQ-TTS-004`)

The engine MUST release its CoreML models on a memory-pressure notification when
**no session is active**, and re-warm lazily afterwards. Releasing mid-utterance
is worse than the pressure it relieves.

Peak RSS with the engine warm **and** the Foundation Models session resident MUST
be measured and recorded in spec 036's metrics table. This co-residency is the
family's least-understood risk: the app already holds an on-device LLM, and
nothing has yet measured what a second model costs alongside it.

> **Amended 2026-08-18 — "oldest supported device" is now defined, and there are
> two of them.** This requirement, 031 R5, and 036's gate table all used that
> phrase; **no spec ever defined it**, which meant every memory and latency budget
> in the family rested on an unstated baseline. Memory and compute have different
> worst cases and conflating them hides risk:
>
> | Floor | Device | Binding for |
> |---|---|---|
> | **Memory floor** | Oldest **Apple Intelligence** device | Peak RSS — the only place 243 MB of weights competes with a resident LLM |
> | **Compute floor** | Oldest supported device (`CapabilityTier.reduced`) | Synthesis RTF and cold-open — slowest ANE, and no AFM to compete with |
>
> **This requirement's measurement belongs to the memory floor.** R5's placement
> and the RTF figures belong to the compute floor, because a Reduced-tier device
> runs the neural voice too (030 R5, amended) and is the slowest hardware that
> will ever execute this graph.
>
> The practical consequence is that neither floor alone is sufficient evidence:
> a flagship RSS number proves nothing about the memory floor, and an
> Apple-Intelligence-device RTF number proves nothing about the compute floor.

**Acceptance (Given/When/Then):**
- Given simulated memory pressure with no active session, when it fires, then
  models are released and the **next** synthesis re-warms transparently — the
  user observes latency, never failure.
- Given memory pressure **during** an utterance, when it fires, then the
  in-flight utterance completes and release happens after drain.
- Given the **memory floor** device, when engine and AFM are both resident, then
  peak RSS is measured and recorded (036) — and if it exceeds the headroom that
  device allows, that is an escalation, not a tuning note.
- Given the **compute floor** device, when synthesis runs, then RTF and cold-open
  are measured and recorded (036), with no AFM resident.

### R7. Cancellation is prompt, and it is load-bearing (`REQ-TTS-004`)

Every synthesis call accepts cooperative Swift `Task` cancellation, and cancelled
work MUST stop consuming ANE/GPU **promptly** — not at the next natural
boundary. This is not a tidiness requirement: it is the mechanism behind
tap-to-interrupt today (028 R5) and acoustic barge-in later (034), where the
budget is 150 ms from voice detection to silence. An engine that finishes its
current chunk before noticing cancellation spends most of that budget by itself.

**Acceptance:** given a synthesis in flight, when the task is cancelled, then the
task ends within **100 ms**, no buffer is emitted, and no partial audio reaches
the player node — measured, 20-trial median.

### R8. Errors degrade; they never crash (`REQ-TTS-003`)

Any engine failure — load, verification, inference, format — falls back to the
`AVSpeechSynthesizer` path **for that utterance** and logs a structured event.
The user hears speech either way. There is no error dialog for a synthesis
failure; the correct behavior is that they notice a different voice, or nothing
at all.

Structured logging follows spec 029 R1's rules: `os.Logger` with privacy
annotations, durations and error kinds only, **never the text being spoken**.

**Acceptance:** given a forced engine error, when an utterance is requested, then
it completes via the system-voice fallback, one structured event is logged with
no plaintext, and no alert is presented.

### R9. Testability (derived)

The engine is exercised through a protocol seam with a hand-written fake,
matching the repo's existing convention (`NarrationSpeechListening` /
`NarrationVoicePlayback` in `NarrationCoordinator.swift`, `MockSynthesizer` in
`VoicePlaybackServiceTests`). Unit tests run **without CoreML**: warm-up
idempotence, style-switch-emits-no-reload, cancellation timing against a
scriptable fake, fallback-on-error routing, and buffer-drain ordering are all
pure-logic or fake-driven.

Anything requiring the real model is a device task, marked in-source with a
`MEASURE-ON-DEVICE` comment so it is greppable rather than forgotten.

**Acceptance:** the `MeetMementoTests` suite stays green and gains no CoreML
dependency; every device-only measurement carries a `MEASURE-ON-DEVICE` marker.

## Non-goals

- Chunking, streaming policy, and the turn-start mask — spec 032.
- The voice catalog, display naming, and picker — spec 033.
- Any `AVAudioSession` category or voice-processing change — 028 owns the current
  configuration, 034 owns the future one. **This spec must not touch session
  configuration**; it schedules buffers into a session someone else activated.
- Spoken-form normalization and expression tags — spec 035.
- Now Playing duration and a real scrubber. Unblocked by this engine
  (`technology/13` §4, 018 R7) but deliberately not built here.
- Retiring `AVSpeechSynthesizer`. Permanent, per CONSTITUTION rule 11.

## Acceptance

1. **Device:** ANE placement measured and recorded (V29); `DEC-008` resolved in
   writing before any bucketing work.
2. **Device:** synthesis of a 2 s sentence completes at ≤ 0.25× realtime on
   current-generation hardware, with the actual real-time factor recorded
   (target 0.15). Measured on the oldest supported device too — that number is
   the one that matters.
3. **Device:** peak RSS with engine warm + AFM resident, measured and recorded.
4. **Device:** cancellation → task end within 100 ms, 20-trial median.
5. **Unit:** `prepare()` twice → second call < 5 ms; style switch logs no reload;
   forced error routes to system-voice fallback; memory-pressure release then
   transparent re-warm; drain ordering uses `DataPlayedBack`.
6. **CI:** `Single CoreML importer (spec 031 R1 / REQ-TTS-004)` live and proven
   to fail on a planted violation.
7. **Regression:** tap-to-read, inline dictation, journal dictation, the settings
   voice preview, and 028's four-consecutive-turn hands-free run all behave
   unchanged.

## Regression Guards

- **CONSTITUTION §2 (2026-08-18)** — the audio-session ordering machinery
  (`sessionGeneration`, `waitForSessionRelease()`, `shouldReleaseAudioSession`,
  activation buffering) is a non-regression asset. Every guarantee it makes must
  survive the new playback path. Rewriting it "more cleanly" reintroduces a bug
  class that produces no error, no crash, and no log line — only a conversation
  that stops after one turn.
- **CONSTITUTION §2** — the utterance-session seam. Callers must remain unable to
  tell which engine is serving.
- **CONSTITUTION rules 11 and 12** — fallback permanent; synthesis on-device.
- **CONSTITUTION rule 10** — nothing built against V29 while it is 🔴.
- **Spec 028 R2** — half-duplex remains in force until 034 is claimed. This spec
  introduces an output graph, **not** a duplex session.
- **Spec 029 R1** — no plaintext in any signpost or perf log, including the new
  `tts.synth` stage.

## Appendix — interface sketch

Contract, not implementation.

```swift
/// Zone: .z0Device (spec 014 R1). The ONLY module importing CoreML (R1).
actor SupertonicEngine {
    static let shared: SupertonicEngine

    func prepare() async throws            // idempotent warm-up (R3)
    var isWarm: Bool { get }

    /// Native mono Float32 PCM. Cooperatively cancellable (R7).
    func synthesize(text: String,
                    style: VoiceStyle,
                    language: String = "en") async throws -> AVAudioPCMBuffer

    func releaseForMemoryPressure()        // R6
}

/// AVAudioEngine + AVAudioPlayerNode. Schedules buffers; owns no session state.
/// Completion observed as .dataPlayedBack, never .dataConsumed (R2).
protocol TTSPlayback {
    func enqueue(_ buffer: AVAudioPCMBuffer)
    func flushAndStop()
    var completions: AsyncStream<Void> { get }
}
```
