---
id: 032
title: TTS Streaming Pipeline and Perceived Latency
tier: P1
status: in-progress (2026-08-19) — First-chunk fast path + TurnStartMask skip-if-missing; unmasked latency probe for 036
effort: 1 session
depends_on: [028, 029, 031]
findings: [snapshot-streaming-not-token-streaming, engine-128-token-input-ceiling, first-chunk-shorter-than-steady, turn-start-mask-in-selected-voice, mask-must-not-hide-regression, bounded-lookahead-beats-buffer-depth]
source_refs: [REQ-TTS-005, REQ-PERF-001, REQ-PERF-002, REQ-NAR-001]
tech_refs: [technology/13-neural-tts-coreml.md, technology/06-speech-and-audio.md]
---

# 032 — TTS Streaming Pipeline and Perceived Latency

**Traceability:** implements `REQ-TTS-005` on the engine from
`specs/031-neural-synthesis-engine.md`, inside the conversation loop defined by
`specs/028-conversational-narration.md` R1, instrumented per
`specs/029-performance-and-speech-excellence.md` R1–R2 (both extended
2026-08-18). Extends the shipped `StreamingSentenceChunker`; does not replace it.

## Why

A conversation is judged on the gap between "I stopped talking" and "it started
talking." Everything else — voice quality, answer quality — is evaluated only
after that gap has already made its impression.

The budget decomposes roughly as: 300–600 ms to the model's first sentence,
100–300 ms to synthesize the first chunk, 10–50 ms to start audio. Nothing there
is individually fixable by much. What *is* fixable is that the entire game is the
**first 800 ms** — after chunk one, a pipelined engine never underruns — and that
a short acknowledgment in the user's own selected voice converts most of that
gap from dead air into presence.

The discipline this spec insists on: the mask is allowed to improve the
*experience*, and never allowed to hide the *measurement*.

## Technology References

- `specs/reference/technology/13-neural-tts-coreml.md` §4 — buffer scheduling and
  the `DataPlayedBack` completion type (**✅ VERIFIED**, iOS 27.0 SDK).
- `specs/reference/technology/06-speech-and-audio.md` §B1 (amended 2026-08-18) —
  why mid-stream synthesis is legitimate on this path and not on the fallback.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | **Streaming is snapshot-based, not token-based.** Any design specifying a per-token chunker does not match the model this app actually uses | `MeetMemento/Services/Intelligence/FoundationModelsIntelligenceService.swift` — `for try await snapshot in stream`, each snapshot carrying the whole `content.body` so far; surfaced as `AskStreamEvent.delta(bodySoFar:…)` in `IntelligenceService.swift` | **Critical** — a token-timeout chunker is unimplementable as written |
| 2 | A sentence chunker already exists, is tuned, and is unit-tested | `MeetMemento/Utilities/StreamingSentenceChunker.swift:58` `consume(_ cumulative:isFinal:allowStableTail:)`; constants `minSentenceLength = 15` (`:30`), `firstClauseMinWords = 12` (`:33`), `firstPrefixMinWords = 10` (`:36`), `stableTailMinWords = 12` (`:38`); `StreamingSentenceChunkerTests` | — (asset to extend) |
| 3 | The first-chunk-shorter policy is **already implemented**, under different names than the draft design uses | `StreamingSentenceChunker.firstChunkPrefix(_:)` (`:182`) emits an early first chunk on a clause boundary or a stable word prefix; `reconcileOpener` handles the "Sure." fast path | Medium — extend, don't reinvent |
| 4 | Latency instrumentation for exactly these stages already exists | `MeetMemento/Utils/TurnTimings.swift:22–25` — `.firstSentence`, `.ttsActivate`, `.ttsFirstAudio`, `.listenRearm`; `MeetMemento/Utils/PerfSignposts.swift:25` `speechLoop` category | — (asset to extend) |
| 5 | Nothing measures synthesis cost or playback underruns, because neither existed | No `tts.synth` stage, no underrun counter (029 R1, extended 2026-08-18) | Medium |
| 6 | There is no turn-start acknowledgment of any kind; the gap is currently silent | `NarrationFooter` shows "Thinking…" — a visual affordance for an audio problem | Medium — the gap is felt, not seen |

## Requirements

**Traceability:** R1 → `REQ-TTS-005` (chunking); R2 → `REQ-TTS-005` (pipelining);
R3, R4 → `REQ-TTS-005` (mask); R5 → `REQ-INT-` prompt contract, owned jointly with
spec 017's `PromptRegistry`; R6 → `REQ-PERF-001`/`002`.

**Zone declaration:** `.z0Device`. Chunking and masking are local text and audio
operations over material already on the device.

### R1. Chunking extends the shipped chunker, in its own vocabulary (`REQ-TTS-005`)

`StreamingSentenceChunker` remains the single chunking implementation. It already
consumes **cumulative snapshots** — which is what the model emits — and already
tracks `emittedCount` by count rather than offset, because the body can shrink
when reference markers are stripped. Both properties are load-bearing and neither
is obvious; do not rewrite it.

This spec extends it with:

- **A first-chunk policy that is explicitly shorter than steady state.** Already
  present as `firstChunkPrefix(_:)` with `firstPrefixMinWords = 10` /
  `firstClauseMinWords = 12`; this requirement makes it normative and ties it to
  the latency gate rather than leaving it a tuning constant.
- **Growth toward steady state**, so later chunks are longer and prosody seams
  become rarer as the reply proceeds. Seams are most forgivable at the start,
  when the listener is still orienting.
- **Terminal-punctuation and stream-end emission**, unchanged.

> **⚠️ Hard ceiling discovered 2026-08-18 — 128 tokens per synthesis call.**
> The engine's `TextEncoder` and `DurationPredictor` are fixed-shape at
> `text_ids [1,128]` with an explicit `text_mask` (`technology/13` §3, verified by
> compiling the bundle). **Text longer than 128 tokens cannot be synthesized in
> one call** — the app must split it.
>
> This is a **correctness constraint on the chunker, not a tuning knob.** Every
> chunk handed to the engine MUST tokenize to ≤128 tokens, and the chunker needs a
> hard fallback split for the pathological case: a "sentence" that exceeds the
> ceiling on its own (a run-on, a pasted URL, a list the prompt failed to
> suppress) must be split mid-sentence rather than dropped or truncated.
> Truncation would silently swallow user-facing words, which is the worst
> available failure.
>
> It happens to push the same way the latency design already wanted — shorter
> chunks — but it binds whether or not that stays true. Note the ceiling is in
> **tokens**, not words or characters; the chunker's existing vocabulary is
> word-based, so the mapping needs a conservative margin rather than an exact
> conversion.

**Prosody seams are a first-class concern, because the ceiling makes splits
mandatory** (added 2026-08-18). Flow-matching synthesis carries no state across
calls, so pitch and energy contour restart at every chunk. When chunks fell on
sentence boundaries that was inaudible — sentences restart contour anyway. A
forced mid-sentence split does not have that excuse. Three mitigations, in
priority order:

1. **Prefer prosodic split points.** When a split is forced, choose a clause or
   comma boundary over an arbitrary word gap, so the break lands where a speaker
   would have drawn breath. Only fall back to a bare word boundary when no
   prosodic candidate exists inside the budget.
2. **Hold the style vector constant** across every chunk of one utterance. The
   engine takes `style_ttl` per call, so passing a different or re-derived vector
   mid-utterance would shift *timbre* as well as contour — a much more noticeable
   artefact than a contour reset. Same voice id, same vector, whole utterance.
3. **Never let a seam also be a silence** — R2's gapless scheduling.

**Acceptance:** given a paragraph that forces at least one mid-sentence split,
when the split point is inspected, then it falls on a prosodic boundary wherever
one exists within the token budget — asserted over a fixture corpus, with the
no-candidate fallback exercised explicitly.

**Two different "tokens" — do not conflate them.** The draft that motivated this
family specified a 12-token first-chunk timeout and a 24-token steady timeout,
counting *model output* tokens. Those do not exist here: Foundation Models emits
cumulative **snapshots**, not token events, so a token timeout would never fire
and the pipeline would silently never emit an early first chunk. Translate those
into the word-count constants above.

The 128 above is the opposite direction — *engine input* tokens, a hard ceiling
the chunker must respect. One is an unavailable trigger; the other is a binding
limit. Only the second is real.

**Acceptance (Given/When/Then):**
- Given a scripted snapshot stream with realistic timing, when consumed, then the
  first emitted chunk is strictly shorter than the steady-state median — asserted
  by unit test over a fixture corpus.
- Given a reply arriving as one long unpunctuated run, when it streams, then
  chunks still emit on the stable-tail rule rather than waiting for the end.
- Given the existing `StreamingSentenceChunkerTests`, when this work lands, then
  they pass unmodified or their changes are justified in the PR.
- Given a single "sentence" that alone exceeds 128 engine tokens, when it is
  chunked, then it is **split**, every word survives to synthesis, and nothing is
  truncated — asserted by unit test with a deliberately pathological fixture.
- Given any chunk emitted to the engine, when tokenized, then it is ≤128 tokens —
  asserted as an invariant, not sampled.

### R2. Pipelining with bounded lookahead (`REQ-TTS-005`)

Synthesis of chunk N+1 begins while chunk N plays. **At most two chunks of
synthesized audio are buffered ahead.**

The cap is deliberate and counterintuitive: deeper buffering makes underruns less
likely, and makes barge-in worse. Every buffered chunk is audio that must be
discarded — and stopped — when the user interrupts. Responsiveness to
interruption beats smoothness, because a user talking over an assistant that
keeps talking is a worse experience than a 100 ms seam.

At the engine's target real-time factor the pipeline does not underrun after
chunk one anyway, which is what makes the shallow buffer affordable.

> **Added 2026-08-18 — playback is gapless, and that is a requirement rather than
> an aspiration.** Chunk boundaries MUST be **sample-accurate**: buffers are
> scheduled contiguously onto the player node so that no silence is inserted
> between them.
>
> This is a capability the fallback path never had and whose budgets must not be
> inherited. `AVSpeechSynthesizer` needs `postUtteranceDelay` (currently `0.1 s`,
> `VoicePlaybackService.swift:286`) and 029 R2 budgets an inter-sentence gap of
> **≤ 0.35 s** — both are concessions to a synthesizer that speaks whole
> utterances and cannot be joined seamlessly. Scheduling PCM buffers back to back
> has no such constraint, so **the neural path's inter-chunk gap target is zero**,
> not 0.35 s.
>
> It matters more here than it would elsewhere, because the 128-token ceiling
> (R1) makes splits *mandatory* rather than incidental. A forced split that is
> also an audible pause turns an engine limitation into a speech impediment. Get
> this wrong and every long sentence in the product stutters.

**Acceptance (Given/When/Then):**
- Given a 60 s multi-chunk narration on target hardware, when it plays, then
  **zero underruns** are recorded.
- Given two consecutive chunks of one utterance, when the output is captured and
  measured, then the inter-chunk gap is **zero samples** — asserted against the
  rendered buffer, not judged by ear.
- Given narration in flight, when the lookahead is inspected, then no more than
  two synthesized chunks are held.
- Given an interruption, when it fires, then buffered-but-unplayed chunks are
  discarded, not drained (034 R4 measures the resulting time-to-silence).

### R3. Turn-start mask — in the user's voice, or not at all (`REQ-TTS-005`)

On end-of-user-speech, a pre-rendered acknowledgment clip of **200–300 ms** plays
in the user's **currently selected voice** while the first real chunk synthesizes.

The clips are rendered at build time and bundled (spec 030 R4), one per voice.
**A mask in the wrong voice MUST be impossible by construction** — lookup is keyed
by the same `VoiceStyle.id` as synthesis, so there is no code path where the two
can disagree. This is stated as a construction requirement rather than a test
requirement on purpose: a wrong-voice mask is uncanny in a way a slow response
never is, and it would appear only in the moment the user is most attentive.

**Acceptance (Given/When/Then):**
- Given each of the four voices, when a turn starts with the mask engaged, then
  the mask sounds in that voice — parameterized test across the full catalog.
- Given a voice id with no mask clip, when a turn starts, then the mask is
  **skipped silently** and the turn proceeds — a missing clip degrades to the
  status quo, never to a wrong voice.
- Given the mask playing, when the first real chunk becomes ready, then the
  transition is contiguous with no overlap and no double-start.

### R4. Mask suppression, and the rule that the mask never lies (`REQ-TTS-005`)

- If the first real chunk is ready within **250 ms**, the mask is **skipped** — a
  mask that plays before speech that was already arriving adds latency instead of
  hiding it.
- A mask MUST NOT play twice for a single turn.
- Barge-in during a mask cancels it exactly as it cancels real speech (034 R5).

**And the rule this requirement exists for:** the mask changes perceived latency,
never measured latency. Both figures are logged every turn (R6) and both are
gates in spec 036. A regression in `tts.firstAudio` that the mask conceals is
still a regression, and the unmasked number is what catches it.

**Acceptance (Given/When/Then):**
- Given synthesis completing in under 250 ms, when the turn starts, then no mask
  plays.
- Given a 20-turn scripted session, when logs are inspected, then no turn shows
  two mask starts.
- Given a deliberately slowed engine, when turns run, then perceived and
  instrumented latencies diverge in the logs — proving both are recorded
  independently rather than one being derived from the other.

### R5. The prompt asks for spoken register (owned jointly with 017)

Conversation-mode prompts MUST request spoken register: contractions, 8–14 word
sentences, fragments allowed, no lists, no markdown, and a **short first
sentence**. The last item is a latency lever as much as a style one — the first
chunk cannot be short if the model's first sentence is long.

This requirement lives here because it is a latency mechanism; the prompt text
itself lives in spec 017 R8's `PromptRegistry`, which owns prompt content. Cite,
do not duplicate. `REQ-VOX-006` and the `SpeakabilityLinter` (018 R9) continue to
apply unchanged — a better voice does not make markdown speakable.

**Acceptance:** given conversation-mode generations over the evaluation corpus,
when linted, then `SpeakabilityLinter` passes and median first-sentence length
falls within the requested band.

### R6. Instrumentation from the first commit (`REQ-PERF-001`)

Per-turn logging of: `endOfUserSpeech → firstAudibleSample` **masked and
unmasked**, chunk count, per-chunk synthesis real-time factor, and underrun
count. These extend `TurnTimings` and the `speech.loop` signpost category
(029 R1, extended) — they do **not** become a parallel instrumentation system.

Local structured logs only. **No analytics egress**, per the product
constitution; and per 029 R1's rule, durations and counts only — never the text
being spoken.

Retrofitting instrumentation after a latency regression means measuring a system
you have already changed, so this ships with the first commit of the pipeline,
not at the end.

**Acceptance:** given a 20-turn scripted session, when logs are parsed, then
every turn yields a complete, parseable record with both latency figures, and no
log line contains user text.

## Non-goals

- The engine, warm-up, and cancellation mechanics — spec 031.
- Acoustic barge-in and the AEC path — spec 034. Interruption here means the
  existing tap-to-interrupt (028 R5).
- Spoken-form normalization and expression tags — spec 035; the formatter runs on
  each chunk *before* synthesis, and this spec must not duplicate it.
- Prompt authorship — spec 017 R8.
- Streaming-input synthesis (token-level, Orca-style). Revisit only if the masked
  turn-start fails its gate in real use.
- Changing the visual "Thinking…" affordance. The mask is an audio answer to an
  audio problem.

## Acceptance

1. **Device:** first audible output ≤ **400 ms** perceived with the mask engaged;
   instrumented unmasked ≤ **900 ms**. Both recorded (036).
2. **Device:** zero underruns across a 60 s multi-chunk narration.
3. **Device:** mask sounds in the correct voice for all four voices.
4. **Unit:** mask suppressed when synthesis beats 250 ms; never double-fires;
   missing clip degrades to no mask.
5. **Unit:** first chunk strictly shorter than steady-state median over a fixture
   corpus; existing `StreamingSentenceChunkerTests` still green.
6. **Unit:** lookahead never exceeds two synthesized chunks.
7. **Logs:** 20-turn scripted session yields complete parseable latency records,
   masked and unmasked, with no user text.

## Regression Guards

- **Spec 028 R1/R3** — the loop and its session ordering. This spec changes what
  is spoken and when, never who releases the audio session or in what order.
- **Spec 028 R2** — half-duplex remains in force; nothing here opens a mic during
  playback.
- **Spec 029 R1/R2** — extends the existing instrumentation and stays inside the
  no-plaintext rule. The masked figure never replaces the instrumented one in any
  report.
- **Spec 018 R9 / `REQ-VOX-006`** — speakability still enforced;
  `SpeechTextSanitizer` still applies at its single choke point.
- **CONSTITUTION §2** — the utterance-session seam is unchanged by this work.

## Appendix — interface sketch

Expressed in the shipped chunker's vocabulary, not in tokens.

```swift
struct ChunkerConfig {
    /// Already shipped as StreamingSentenceChunker.firstPrefixMinWords / firstClauseMinWords.
    var firstChunkMinWords = 10
    var firstClauseMinWords = 12
    /// Steady state: longer chunks, fewer prosody seams.
    var steadyMinWords = 12
    var maxLookaheadChunks = 2      // R2 — responsiveness beats depth
}

enum TurnStartMask {
    /// Bundled, per-voice. Keyed by the SAME id as synthesis (R3):
    /// a wrong-voice mask is unrepresentable, not merely untested.
    static func clip(for styleID: String) -> AVAudioPCMBuffer?
}
```
