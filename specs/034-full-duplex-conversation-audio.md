---
id: 034
title: Full-Duplex Conversation Audio — AEC and Barge-in
tier: P2
status: not-started
effort: 2 sessions
depends_on: [018, 028, 031, 032]
findings: [supersedes-half-duplex-invariant-on-conversation-path, no-vad-source-exists-yet, voice-processing-degrades-timbre, sample-rate-conversion-on-conversation-path, voice-processing-state-must-not-leak]
source_refs: [REQ-TTS-007, REQ-NAR-002, REQ-NAR-003, REQ-NAR-005, REQ-VOX-005, DEC-009]
tech_refs: [technology/13-neural-tts-coreml.md, technology/06-speech-and-audio.md]
---

# 034 — Full-Duplex Conversation Audio — AEC and Barge-in

**Traceability:** implements `REQ-TTS-007`. **This spec is the named successor to
`specs/028-conversational-narration.md` R2's half-duplex invariant** (amended
2026-08-18), which it supersedes **on the conversation path only** once this
spec's status moves off `not-started`. Until then, 028 R2 binds in full. Builds
on 028 R3's session-ordering machinery, the engine from `031`, and the streaming
pipeline from `032`. Shares `DEC-009` / V30 with `033`.

## Why

Hands-free conversation is half-duplex today: the mic closes while the assistant
speaks, so interrupting requires reaching for the phone — which is the one thing
hands-free mode exists to avoid. The gap between "I can talk to it" and "I can
talk **over** it" is the difference between a voice interface and a walkie-talkie.

Closing it needs echo cancellation: with the mic open during playback, the
recognizer otherwise hears the assistant and transcribes it as the user.

This is P2 and deliberately off the critical path, for two reasons that are
about capability rather than scheduling. **There is no voice-activity source in
the app** — `SpeechService` is still legacy `SFSpeechRecognizer`, and
`SpeechDetector` arrives with spec 018 R1's `SpeechAnalyzer` migration, which is
not done. And voice processing measurably **degrades voice character**, so the
roster it will run through must be auditioned first (V30). Shipping the neural
voice does not wait for either.

The architecture is still specified now, in full, because the dual-path controller
is what 028's ordering machinery grows into — and because a conversation path
retrofitted later, around code that assumed one audio configuration forever, is
the expensive version of this.

## Technology References

- `specs/reference/technology/13-neural-tts-coreml.md` §5 —
  `setVoiceProcessingEnabled:error:` and the AGC/ducking/mute properties
  (**✅ VERIFIED**, `AVAudioIONode.h`, iOS 27.0 SDK 27A5228h, 2026-08-18); the
  timbre cost (🔴, V30); the sample-rate risk (🔴).
- `specs/reference/technology/06-speech-and-audio.md` §A4–A5 — session durability
  and route behavior; §B5 — audio-app expectations for the read-back path.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | Two services own two categories and never overlap; there is no controller above them | `MeetMemento/Services/VoicePlaybackService.swift:678` `setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])` vs `MeetMemento/Services/SpeechService.swift` `.record`/`.measurement` | High — the dual path needs an owner |
| 2 | **No voice processing anywhere.** No AEC, no `AVAudioInputNode` configuration for it | `grep -rn 'setVoiceProcessingEnabled\|voiceProcessing' MeetMemento/` → zero hits (2026-08-18) | High — greenfield |
| 3 | **No VAD / `SpeechDetector` exists**, so acoustic barge-in has no trigger | `SpeechService.swift` uses `SFSpeechRecognizer` + `SFSpeechAudioBufferRecognitionRequest`; `SpeechAnalyzer`/`SpeechTranscriber`/`SpeechDetector` appear nowhere in app code — 018 R1 owns that migration and is not done | **Critical** — gates R4's acoustic half |
| 4 | Barge-in today is user-initiated only, and cannot be otherwise while the mic is closed | `MeetMemento/ViewModels/NarrationCoordinator.swift` `micTapped()` in `.speaking` → `voiceService.stop()` | — (the interim behavior R4 preserves) |
| 5 | The ordering machinery this spec must subsume is subtle and hard-won | 028 R3: `waitForSessionRelease()` (`VoicePlaybackService.swift:648`), `shouldReleaseAudioSession(...)`, `sessionGeneration` counters, activation buffering | **Critical** — subsume, never bypass (CONSTITUTION §2) |
| 6 | Sample rates will not match on this path | Engine emits 44.1 kHz (`technology/13` §1); voice-processing I/O commonly negotiates 48 kHz, some routes 16 kHz (`technology/13` §5); `SpeechService.convertTo16kMono` is the existing precedent for a conversion stage | Medium — "no conversions" is false here |
| 7 | Now Playing is published unconditionally by the playback service | `VoicePlaybackService` `publishNowPlaying(title:)` / `registerRemoteCommands()`, per `REQ-VOX-005` | Medium — correct for read-back, wrong for a live session |

## Requirements

**Traceability:** R1 → `REQ-TTS-007` (two paths); R2 → `REQ-TTS-007` +
`REQ-NAR-003` (transitions); R3 → `REQ-TTS-007` (echo integrity); R4 →
`REQ-TTS-007` + `REQ-NAR-005` (barge-in); R5 → `REQ-TTS-007` (format boundary);
R6 → `REQ-VOX-005` (Now Playing and interruptions); R7 → this spec's supersession
of `REQ-NAR-002`.

**Zone declaration:** `.z0Device`. Echo cancellation is signal processing on the
device's own I/O; STT remains on-device-only
(`requiresOnDeviceRecognition = true`, 018 R1 interim, 028 R7). This spec adds
**no** new capture, storage, or network path — it changes when the existing mic is
open, not where anything goes.

### R1. Two named audio paths, one owner (`REQ-TTS-007`)

`ConversationAudioController` owns both configurations. Nothing else changes an
`AVAudioSession` category.

- **Read-back path** — `.playback`, high fidelity, **no voice processing**. Used
  for narration and read-aloud. This is the shipped configuration
  (`VoicePlaybackService.swift:678`) and it does not change.
- **Conversation path** — `.playAndRecord` with voice processing enabled on the
  engine's I/O node (AEC + AGC). Used **only** in hands-free mode.

The read-back path staying pristine is the point of having two. Voice processing
is a tax paid for the ability to be interrupted, and a user listening to a Sunday
reflection on a walk is not being interrupted by anyone.

**Acceptance (Given/When/Then):**
- Given the app, when audio-session configuration calls are audited, then every
  one originates in `ConversationAudioController` — asserted by a source-level
  check, not by convention.
- Given read-back after conversation mode has run, when output is compared
  against read-back on a cold launch, then it is **identical** — no leaked
  voice-processing state (see R7's A/B check).

### R2. Transitions are explicit state-machine events (`REQ-NAR-003`)

Path changes are events on a state machine, never implicit side effects of
playback or capture code. This preserves 028 R3's guarantees in a world with more
states, and it must **subsume** that machinery rather than route around it:
generation-guarded release, awaitable session release, activation ordering, and
buffering until activation lands all still apply.

Route changes — AirPods connecting or disconnecting mid-turn — MUST be handled
**without killing an in-flight turn**.

CONSTITUTION §2 names this machinery a non-regression asset for a specific reason:
every guarantee in it exists because a silent failure was traced to its absence.
A cleaner-looking session layer that does not reproduce them reintroduces a bug
that produces no error, no crash, and no log line — just a conversation that stops
after one turn.

**Acceptance (Given/When/Then):**
- Given a path transition, when it runs, then it is one state-machine event with
  the prior session fully released first — asserted by unit test against the
  existing pure decision helpers.
- Given AirPods disconnecting mid-turn, when it happens, then audio continues on
  the speaker within the same turn, or the turn ends cleanly. **No stuck
  session** in either case.
- Given 028's four-consecutive-turn hands-free device run, when re-run on the
  conversation path, then it still passes.

### R3. Echo integrity — our voice never becomes their words (`REQ-TTS-007`)

With AEC engaged, TTS output MUST NOT appear in the user transcript.

This failure mode is worse than it sounds: a transcript polluted with the
assistant's own words is fed back as conversation history, so the model reads its
own output as something the user said. The conversation degrades in a way that
looks like the model losing its mind rather than like an audio bug.

**Acceptance (Given/When/Then):**
- Given a scripted 10-turn session in a **quiet room**, when the transcript is
  inspected, then it contains **zero** TTS-origin phrases.
- Given the same session in a **moderate-noise room**, then the same result.
- Given the mask clip playing (032 R3), then it likewise never appears in the
  transcript — short clips are the easiest case to forget.

### R4. Barge-in — acoustic where possible, tap always (`REQ-NAR-005`)

Voice-start detection → `TTSPlayback.flushAndStop()` → cancel in-flight and
queued synthesis (031 R7) → **measured time-to-silence ≤ 150 ms**. The
interrupted turn's remaining text is **discarded, not resumed**: a person who
interrupts has changed the subject, and resuming answers a question that is no
longer being asked. The typed reply keeps streaming into the chat transcript, as
it does today (028 R5).

**Prerequisite, stated as a requirement rather than a note:** acoustic barge-in
requires a voice-activity source, and none exists (evidence row 3). It is gated on
spec 018 R1's `SpeechAnalyzer` migration landing `SpeechDetector`.

**Interim behavior — and it is a real, shippable state:** the conversation path
may activate with **tap-to-interrupt only**, exactly as 028 R5 specifies. The
dual-path architecture, AEC, echo integrity, transitions, and the 150 ms
cancellation budget are all buildable and testable before any VAD exists — the
trigger is the only missing piece, and 031 R7's prompt cancellation is what makes
the budget achievable once it arrives.

**Acceptance (Given/When/Then):**
- Given barge-in (tap now, acoustic later), when it fires, then time-to-silence
  is ≤ **150 ms**, 20-trial median, instrumented.
- Given barge-in, when the turn ends, then remaining chunks are discarded and no
  buffered audio plays afterward.
- Given a mask clip playing, when barge-in fires, then it is cancelled
  identically to real speech (032 R4).
- Given `SpeechDetector` unavailable, when hands-free mode runs, then
  tap-to-interrupt works and **nothing hangs waiting for a VAD**.

### R5. Format conversion is acknowledged, not wished away (`REQ-TTS-007`)

The engine emits 44.1 kHz; voice-processing I/O commonly negotiates a different
rate. A conversion stage on the conversation path is therefore **unavoidable** —
`AVAudioConverter`, mirroring the existing `SpeechService.convertTo16kMono`
precedent on the capture side.

Spec 031 R2's "no intermediate files, no conversions before the playback node"
holds on the **read-back** path and is false here. It must not be written into
code comments on this path as though it were a guarantee — a future reader who
believes it will delete the conversion.

Conversion cost counts against R4's time-to-silence and 032's latency budgets and
must be measured, not assumed negligible.

**Acceptance:** given the conversation path on device, when the negotiated I/O
format is logged, then the conversion stage is present, correct, and its cost is
recorded in 036's metrics.

### R6. Now Playing belongs to read-back, not to a live session (`REQ-VOX-005`)

- **Read-back path** integrates with the existing Now Playing machinery
  unchanged: background audio, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`
  (018 R7).
- **Conversation path publishes no Now Playing.** A live conversation is not
  media. Lock-screen transport controls over a two-way session are meaningless —
  there is nothing to scrub, and "pause" has no coherent meaning mid-turn.
- **Phone-call interruptions end the conversation turn gracefully**, leaving a
  clean idle state. Resuming the app returns to idle, not to a half-torn-down
  session.

**Acceptance (Given/When/Then):**
- Given conversation mode active, when the lock screen is inspected, then no Now
  Playing entry exists for it.
- Given read-back active, then transport controls and metadata are present and
  functional (018 R7 unchanged) — real-device check.
- Given a phone call during conversation, when it arrives, then the session
  suspends and the app returns to a clean idle state afterward.

### R7. Supersession and its verification (`REQ-NAR-002`)

When this spec's status moves off `not-started`, it supersedes **028 R2 on the
conversation path only**. The read-back path remains strictly as 028 R2 describes,
permanently. The supersession is recorded in 028 R2's amendment block; that block
is updated with the date when this spec is claimed.

The **A/B listening check** is the guard that makes the supersession safe: read-back
output must be identical whether or not conversation mode has previously been
active in the same app session. Voice-processing state leaking into the hi-fi path
would degrade every read-aloud in the app, silently, and only on devices where a
user had used hands-free mode first — which is exactly the shape of a bug that
survives testing and ships.

**Acceptance:** given read-back after conversation mode, when compared against
read-back on a cold launch, then output is identical — verified by measurement,
not by listening alone.

## Non-goals

- The `SpeechAnalyzer` / `SpeechTranscriber` / `SpeechDetector` migration itself —
  **spec 018 R1 owns it.** This spec consumes the detector; it does not build it.
- A global `AudioSessionArbiter` actor across all services — 028's non-goal
  stands; the right shape for full duplex is this controller, not a general
  arbiter.
- The engine, chunking, and the voice catalog — specs 031, 032, 033.
- Changing the conversation loop's phases or auto-send heuristics — 028 R1/R4.
- Voice roster selection. `DEC-009` is owned by 033; this spec provides the path
  that audition runs through.
- Speakerphone or CarPlay-specific conversation tuning.

## Acceptance

1. **Device:** barge-in time-to-silence ≤ **150 ms**, 20-trial median.
2. **Device:** zero TTS bleed into the transcript across a scripted 10-turn
   session, in a quiet room **and** a moderate-noise room.
3. **Device:** AirPods disconnect mid-turn → audio continues on speaker within
   the turn, or the turn ends cleanly. No stuck session.
4. **Device:** phone call during conversation → clean suspend and clean idle on
   return.
5. **Device:** A/B check — read-back output identical with and without prior
   conversation-mode activation.
6. **Device:** 028's four-consecutive-turn hands-free run still passes on the
   conversation path.
7. **Unit:** path transitions are single state-machine events; release ordering
   and staleness guards still hold; barge-in discards queued chunks.
8. **Recorded:** negotiated I/O format and conversion cost (036).

## Regression Guards

- **Spec 028 R3 / CONSTITUTION §2** — the session-ordering machinery is subsumed,
  never bypassed. Every guarantee survives or this spec has failed regardless of
  what else works.
- **Spec 028 R2** — supersession is scoped to the conversation path. Read-back
  never becomes `.playAndRecord`.
- **Spec 028 R4** — the listening liveness watchdog still applies; an AEC path
  that dead-mics silently is the same failure with a new cause.
- **Spec 028 R7 / `REQ-NAR-007`** — STT stays on-device-only. Opening the mic
  during playback changes *when* the mic is open, never *where* audio goes.
- **Spec 018 R7 / `REQ-VOX-005`** — read-back keeps its audio-app behavior.
- **CONSTITUTION rule 11** — the `AVSpeechSynthesizer` fallback still works on
  both paths.
- **CONSTITUTION rule 10** — nothing built against V30 while it is 🔴; the timbre
  cost is a measured input to `DEC-009`, not an assumption.

## Appendix — interface sketch

```swift
enum AudioPath {
    case readBack      // .playback, hi-fi, no voice processing — unchanged from today
    case conversation  // .playAndRecord + voice processing (AEC/AGC)
}

/// The ONLY owner of AVAudioSession category changes (R1).
/// Subsumes spec 028 R3's ordering guarantees — does not replace them (R2).
@MainActor
final class ConversationAudioController {
    func activate(_ path: AudioPath) async throws
    func deactivate() async

    /// routeChange, interruption, bargeIn — explicit events, never implicit transitions.
    var events: AsyncStream<AudioEvent> { get }
}
```
