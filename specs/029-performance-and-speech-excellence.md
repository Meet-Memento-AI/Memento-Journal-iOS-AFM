---
id: 029
title: Performance and Speech Excellence
tier: P1
status: in-progress (2026-08-17) — Instrumentation + optimization sweep authored and landing with this spec; on-device baseline/after tables pending device runs
effort: 2 sessions
depends_on: [017, 018, 022, 028]
findings: [regex-compile-storm, per-turn-session-prefill, send-path-io, final-gated-persistence, generation-watchdog, per-turn-permission-xpc, tts-preactivation, sentence-gap-dead-air, first-sentence-fast-path, typewriter-trails-model, embedding-cold-reembed]
source_refs: [REQ-PERF-001, REQ-PERF-002, REQ-PERF-003, REQ-PERF-004, REQ-PERF-005, REQ-PERF-006, REQ-PERF-007, REQ-PERF-008, REQ-PERF-009]
tech_refs: [technology/01-foundation-models.md, technology/06-speech-and-audio.md, technology/04-evaluations.md]
---

# 029 — Performance and Speech Excellence

**Traceability:** enforces the latency budgets minted in
`specs/019-surfaces.md` (composer interactive < 400 ms cold, `019:83`; p50
generation < 2 s on the minimum Apple Intelligence device, `019:138`),
executes the "revisit when latency numbers exist" deferral in
`specs/017-intelligence-boundary-and-prompt-architecture.md` (per-turn
instruction re-tokenization, `017:471`), and supplies the measurement layer
`specs/022-evaluation-and-quality-study.md` assumes (`022:268`: token-level
attribution via the Xcode Foundation Models instrument — never custom
timing infrastructure; this spec adds only app-stage `os_signpost`
intervals, which render in the same Instruments trace). Builds directly on
the loop correctness of `specs/028-conversational-narration.md`. Spec
[`039`](039-reply-channels-and-phatic-generation.md) mints per-channel
`maximumResponseTokens` (phatic ~80, continuer ~64, no-RAG companion ≤ 128,
notebook 512). Those caps are **normative**; later perf work MUST NOT raise
them “for consistency” on notebook. Light caps were tightened (039, 2026-08-23)
so a hello stays one spoken sentence plus a question. Phatic/continuer skip retrieve and ask@14 prefill
(039 R2) — that skip is a latency win this spec may measure but must not
undo. Mints the
`REQ-PERF-` series.

## Why

The narration loop is now correct (028) but not yet *fast*. A shipped,
best-in-class voice product answers within a breath and speaks without dead
air; today every turn pays avoidable costs — recompiled regexes on every
streamed snapshot, a cold model session per turn, blocking I/O before the
model starts, two permission XPC round-trips per mic start, a quarter
second of silence after every sentence, and persistence gating the UI's
final event. Nothing is measured, so none of the existing spec budgets are
enforceable. This spec lands measurement first, then removes the verified
costs, then gates the results against budgets.

## Technology References

- `specs/reference/technology/01-foundation-models.md` §latency — the
  Foundation Models instrument is the only sanctioned source of
  prefill/decode attribution.
- `specs/reference/technology/06-speech-and-audio.md` — audio-session
  durability; half-duplex constraint (028 R2) bounds how fast the mic can
  re-arm.
- `specs/reference/technology/04-evaluations.md` — latency columns in the
  eval harness this spec's numbers feed.

## Current State (evidence, confirmed 2026-08-17)

No `os_signpost`/`OSSignposter`/`XCTMetric` exists anywhere in the app or
test targets; the only latency measurement is a total-duration
`ContinuousClock` log in `FoundationModelsIntelligenceService.logOutcome`
emitted through the DEBUG-only `print` in `Utils/Logger.swift`.

Verified per-turn costs:

| # | Cost | Evidence |
|---|---|---|
| 1 | ~17 `NSRegularExpression` compiles + full cumulative-body rescans **per streamed snapshot** (quadratic in reply length); no compiled-regex caching anywhere | `FoundationModelsIntelligenceService.swift:426-460`, `:710-747`; `OutputSafetyScanner.swift`; `SafetyClassifier.swift:115-125`; `TurnClassifier.swift:196-198` |
| 2 | Fresh `LanguageModelSession` per turn; `prewarm()`'s warm session never used for generation → ask@6 instructions re-prefilled every turn | `FoundationModelsIntelligenceService.swift:407`, `:104,143-161` |
| 3 | `prewarm()` builds prompt + session on the main thread, refires on every chat `onAppear` | `ChatViewModel.swift:80`, `FoundationModels:143-153`, `AIChatView.swift` |
| 4 | Per-send: Keychain `getPIN` (legacy-only need); N `stat` syscalls for the entries-cache signature (and one bad file forces full decrypt forever); whole-transcript JSON read + per-message unwrap | `ChatService.swift:171,289,384-399`; `JournalService.swift:202,223-230`; `LocalChatStore.swift:104-114` |
| 5 | Embeddings in-memory only → full corpus re-embed every launch; scalar cosine; per-turn full-text `lowercased()` per entry | `EmbeddingService.swift:38,56-91`; `EntryRetriever.swift:268-278` |
| 6 | Persistence (2× full-file rewrite, pretty-printed, + sessions.json) gates the `.final` event the UI waits on | `ChatService.swift:307-320`; `LocalChatStore.swift:117-122` |
| 7 | No generation timeout — a stalled stream hangs the bubble and narration's awaitingResponse forever | grep: none |
| 8 | Typewriter reveals ≤ remaining/8 chars per 14 ms tick and re-parses the whole shown prefix at ~71 Hz — deliberately trails the model | `AIOutputComponent.swift:115,231-256,452-482` |
| 9 | Mic start per narration turn: 2 permission XPCs, 2 recognizer allocations, fresh engine/converter/tap | `SpeechService.swift:190,356-452` |
| 10 | `postUtteranceDelay = 0.25 s` on every sentence; TTS session activation fire-and-forget (first-word clipping) and deferred until the first sentence exists | `VoicePlaybackService.swift:241-277,424-444` |
| 11 | First `speechVoices()` resolve on the main thread at first narrated reply; Settings calls it during body render | `VoicePlaybackService.swift:92-112,564`; `SettingsView.swift:150` |
| 12 | Chunker holds short openers (< 15 chars) until the next sentence — delays first audio | `StreamingSentenceChunker.swift:30,47-48` |
| 13 | Compact-only voices ship silently; enhanced-voice guidance only deep in Settings | `VoiceSettingsView.swift:30-54` |

## Requirements

**Traceability:** R1 → `REQ-PERF-001`; R2 → `REQ-PERF-002`; R3 →
`REQ-PERF-003`; R4 → `REQ-PERF-004`; R5 → `REQ-PERF-005`; R6 →
`REQ-PERF-006`; R7 → `REQ-PERF-007`; R8 → `REQ-PERF-008`; R9 →
`REQ-PERF-009`.

**Zone declaration:** everything here is `.z0Device` per 014 R1. Signposts
and timings never carry message plaintext (category/duration only); the
embedding disk cache is derived journal data and inherits journal-grade
protection and purge semantics.

### R1. Stage instrumentation (`REQ-PERF-001`)

`OSSignposter` intervals (subsystem = bundle id; categories `chat.turn`,
`speech.loop`, `app.load`; points-of-interest) cover every stage of a turn:
`mic.stop`, `prep.safety`, `prep.classify`, `prep.retrieve`,
`session.create`, `model.ttft`, `model.stream`, `chunk.firstSentence`,
`tts.activate`, `tts.firstAudio`, `listen.rearm`, `persist.turn`,
`app.load.composerInteractive`. A pure `TurnTimings` value aggregates
per-turn stage durations for the DEBUG-only one-line summary and unit
tests. Token-level prefill/decode attribution comes exclusively from the
Foundation Models instrument (022:268). Hot-path logging migrates from
`AppLogger`/print to `os.Logger` with privacy annotations; no plaintext in
any signpost or perf log.

> **Extended 2026-08-18 (spec 032).** The neural path adds stages this list has
> no name for, and spec `032`'s latency requirement is unmeasurable without them:
> `tts.synth` (per-chunk synthesis interval, from which real-time factor is
> derived), `tts.mask` (turn-start acknowledgment clip started / suppressed), and
> an underrun counter for the playback queue. They belong to `speech.loop` and to
> the same `TurnTimings` aggregate — `032` extends this instrumentation, it does
> not build a parallel one. The privacy rule is unchanged and applies to the new
> stages identically: durations and counts only, never text.

### R2. Budgets (`REQ-PERF-002`)

Measured p50 on the minimum Apple Intelligence device unless noted:

| Metric | Budget | Source |
|---|---|---|
| Chat page interactive, cold | < 400 ms | `app.load.composerInteractive`; XCTApplicationLaunchMetric |
| Mic-stop → send dispatched | < 300 ms | `mic.stop` |
| Prep (safety+classify+retrieve), warm | < 250 ms | `prep.*` |
| Send → first token | < 1.2 s | FM instrument + `model.ttft` |
| Send → first spoken word | < 2.5 s | `mic.stop` end → `tts.firstAudio` |
| First sentence available → audio start | < 300 ms | `chunk.firstSentence` → `tts.firstAudio` |
| Inter-sentence gap | ≤ 0.35 s | speech.loop trace |
| TTS drained → mic live | < 500 ms | `listen.rearm` |
| `.final` → UI settled | < 50 ms | `persist.turn` off critical path |
| Full generation, short reply | < 2 s | FM instrument (019:138) |
| Typewriter catch-up after stream end | ≤ 1 s | HUD summary |

> **Amended 2026-08-18.** These budgets were set against `AVSpeechSynthesizer`,
> where "send → first spoken word" is dominated by waiting for a complete first
> sentence. On the neural path the shape of the problem changes: synthesis
> becomes a measurable cost that did not exist (`tts.synth`), model load becomes
> the dominant cold cost, and the turn-start mask makes *perceived* start
> diverge from instrumented start. Spec `032` owns the neural-path budgets and
> spec `036` owns the release gates; **both must be reported alongside the
> instrumented numbers above, never instead of them.** A mask that hides a
> regression in `tts.firstAudio` is a mask doing harm — the unmasked figure stays
> a gate in its own right.

### R3. Turn-path efficiency (`REQ-PERF-003`)

- All safety/classification/stripping regexes are compiled once
  (static storage) and reused; RetrievalPolicy's prior-turn
  re-classification is memoized per send.
- The streamed **safety scan is incremental and exact**: an unsafe phrase
  lies in already-scanned text, in the new suffix, or spans the boundary —
  so scanning the suffix plus a bounded overlap window (≥ the longest
  scanner match) equals a full scan. A body shrink resets the watermark;
  one full scan always runs at stream end as ground truth. The scan is
  never throttled — unsafe text must not render even transiently (026 R7).
  The **marker strip stays full-body but memoized**: stripping is a
  rewriting transform, and prefix-splicing one cannot be proven exact at
  boundary splits — with compiled regexes it is linear with a small
  constant, and identical snapshots (headings settling around an unchanged
  body) skip it entirely.
- Send-path I/O is warm: no per-send Keychain read (one-time legacy flag),
  per-conversation in-memory history (disk once per conversation open), a
  change-counter entries-cache signature (no per-send directory stats), and
  the decrypted-entries cache tolerates individually unreadable files.

### R4. Speech-loop efficiency (`REQ-PERF-004`)

- Mic start skips permission XPC when already granted (synchronous status
  checks; async request only on `.notDetermined`; revalidated on
  foreground); one cached `SFSpeechRecognizer` with cached on-device
  support.
- The TTS audio session **pre-activates during awaitingResponse** (mic is
  fully released post-028), generation-guarded and deactivated on
  cancel/error; the first `speak` never precedes completed activation
  (no first-word clipping).
- `postUtteranceDelay` is 0.1 s uniformly (was 0.25 s per sentence). A
  longer "final breath" is unnecessary — the session release before the
  mic re-arm provides the handoff pause — and delaying the last
  utterance's `didFinish` would eat straight into the re-arm budget.
- The chunker's first emitted sentence per session bypasses the minimum
  length so short openers start audio immediately.
- The auto-send watchdog tightens to 100 ms ticks when within 300 ms of the
  pause threshold (average jitter ~50 ms); `autoSendPause` itself stays
  1.5 s.

### R5. Load path (`REQ-PERF-005`)

Prewarm runs off the main thread, once per launch or personalization
change (not per `onAppear`); session-list and profile reads leave the main
actor; the TTS voice catalog (`speechVoices()`) is resolved during prewarm
and cached — never during a SwiftUI body render.

### R6. Streaming UI (`REQ-PERF-006`)

Delta application is coalesced (≈30 Hz; bodies are cumulative so
last-writer-wins). The typewriter keeps its feel but adapts: reveal rate
scales with backlog and the shown text reaches the full body within 1 s of
stream completion. Parsing is incremental (stable prefix cached; re-parse
from the last block boundary), eliminating the 71 Hz whole-prefix reparse.

### R7. Generation watchdog (`REQ-PERF-007`)

A 30 s no-snapshot deadline (reset on every snapshot) cancels a stalled
generation with a designed `generationTimedOut` error: typed chat surfaces
the existing retry affordance; narration settles the turn and silently
returns to listening (028's no-modal rule).

### R8. Voice quality (`REQ-PERF-008`)

Retrieval-quality voice ranking is unchanged; on a device where resolution
lands on a compact voice, narration shows a **one-time, dismissible** tip
linking to the enhanced-voice guidance (dismissal persisted).

> **Amended 2026-08-18 — the compact-voice nudge retires with the picker.** The
> tip exists to route a user toward a better *system* voice. Once the neural
> catalog is the voice (`DEC-011`, spec `033`), that advice is wrong: the user
> cannot act on it, and the voice they hear on the fallback path is transient by
> construction. Spec `033` removes the banner and
> `PreferencesService.compactVoiceNudgeDismissed` along with it. The **ranking**
> in this requirement stays — it is what picks the fallback voice — as does the
> rule that `AVSpeechSynthesisVoice.speechVoices()` never blocks the main thread.
> If the neural assets are unavailable the user is told nothing about voices;
> they simply hear the best system voice, which is the correct behavior for a
> degradation path nobody chose to be on.

Embedding
disk cache (R3 companion): entry vectors + norms + token sets persist
under Application Support with `.completeFileProtection`, keyed
`entryID + textHash`, purged on entry delete and delete-everything; cosine
uses vDSP.

### R9. Verification gates (`REQ-PERF-009`)

Pure-logic unit tests for every decision helper (regex-cache equivalence,
incremental == full-pass property tests, signature counter, permission
gate, chunker first-sentence, watchdog deadline, timings math); the full
`MeetMementoTests` suite stays green; before/after Instruments traces on
device fill the R2 table; manual device checklist (no clipping, cadence,
10-turn session, corrupt-file send, nudge-once).

## Non-goals

- Per-conversation `LanguageModelSession` transcript reuse — deferred
  unless the FM instrument shows prefill still dominating TTFT after the
  prefill-overlap change; it contradicts 017 R9's stateless architecture
  and needs its own spec treatment.
- Full-duplex audio (028 non-goal stands).
- Any analytics/telemetry beyond local signposts and DEBUG logs.
- Changing `autoSendPause` (1.5 s is a product feel choice, 028 R1).

## Acceptance

1. Instruments trace on device shows all R1 intervals for one typed and
   one narrated turn; FM instrument attributes prefill/decode.
2. Every R2 budget row has a measured p50/p95 before and after; all "after"
   values meet budget on the reference device.
3. Incremental strip/scan property tests prove output identical to
   full-pass at every snapshot (including markers split across the overlap
   window and shrink resets).
4. A narrated 10-turn session shows no first-word clipping, ≤ 0.35 s
   sentence gaps, and re-arm under 500 ms.
5. A stalled generation recovers via timeout in both typed chat (retry
   affordance) and narration (returns to listening).
6. Compact-voice nudge appears exactly once, links to guidance, never
   reappears after dismissal.
7. Full unit suite green; tap-to-read, inline dictation, journal
   dictation, and voice preview unchanged.
