---
id: 028
title: Conversational Narration Mode
tier: P1
status: in-progress (2026-08-17) — Loop shipped with 027; this spec hardens it into a reliable multi-turn conversation
effort: 1 session
depends_on: [017, 018, 027]
findings: [tts-stt-session-handoff-ordering, stale-teardown-generation-guard, listening-liveness-watchdog, premature-final-placeholder, half-duplex-invariant]
source_refs: [REQ-NAR-001, REQ-NAR-002, REQ-NAR-003, REQ-NAR-004, REQ-NAR-005, REQ-NAR-006, REQ-NAR-007]
tech_refs: [technology/06-speech-and-audio.md]
---

# 028 — Conversational Narration Mode

**Traceability:** completes the hands-free voice loop introduced alongside
`specs/027-navigation-redesign.md` (Narration folded into Chat) on top of the
voice-output surface from `specs/018-capture-and-voice-output.md`
(`REQ-VOX-001`–`007`) and the chat pipeline from
`specs/017-intelligence-boundary-and-prompt-architecture.md`. Mints the
`REQ-NAR-` series. The half-duplex constraint and the deferred full-duplex
(`.playAndRecord` + `.voiceChat`) mode are per
`specs/reference/technology/06-speech-and-audio.md` §B1.

## Why

Narration Mode's promise is a *conversation*: speak, hear the reply, keep
going, hands-free, until you close it. The state machine
(`NarrationCoordinator`) ships that loop, but in practice it works **once** —
after the first reply is spoken the mic never comes back, and the session
hangs on "Listening…" until the user exits. A conversation that dies after
one exchange is not a conversation. This spec (a) states the full loop UX and
its persistence guarantees as testable requirements, and (b) names the audio-
session ordering defects that break turn two, with their fixes.

## Technology References

- `specs/reference/technology/06-speech-and-audio.md` — `AVAudioSession`
  durability patterns; §B1 half-duplex constraint (`.playAndRecord` +
  `.voiceChat` voice-processing I/O reserved for a future full-duplex mode).

## Current State (evidence)

The loop exists end-to-end (confirmed 2026-08-17):
`MeetMemento/ViewModels/NarrationCoordinator.swift` (phases idle → listening
→ finalizing → awaitingResponse → speaking → listening), fed by
`SpeechService` (on-device `SFSpeechRecognizer`, `.record`/`.measurement`)
and `VoicePlaybackService` (`AVSpeechSynthesizer`, `.playback`/`.spokenAudio`)
with `StreamingSentenceChunker` narrating the streaming reply per-sentence.
Persistence is already correct: every spoken turn goes through
`ChatViewModel` → `ChatService` → `LocalChatStore` (one JSON log per
conversation), and narration composes with resumed sessions via
`currentSessionId`.

The defect is an ordering asymmetry on the shared `AVAudioSession`:

- STT → TTS is ordered: `SpeechService.stopRecording()` **awaits** engine
  teardown (`setActive(false)`) before the transcript is consumed and TTS
  activates (`SpeechService.swift` `performEngineTeardown`).
- TTS → STT is racy: on queue drain, `VoicePlaybackService.clearSession()`
  publishes `speakingMessageID = nil` — which immediately re-arms the mic —
  while concurrently firing an **un-awaited, un-guarded**
  `Task.detached { setActive(false) }`
  (`VoicePlaybackService.swift` `deactivateAudioSessionIfNeeded`). Landing
  late, that deactivate kills the live record session silently: the tap
  delivers no buffers, `audioLevel` stays exactly 0, no partials arrive,
  auto-send never fires, nothing throws.

A second, independent loop-killer (found by the R8 unit tests, 2026-08-17):
`consumeReplyProgress` read finality as `!message.isStreaming`, but the
assistant placeholder is appended with `isStreaming == false` (it flips on
the first delta) — so the messages hop that runs before any delta reads the
empty placeholder as a settled empty reply, marks the turn settled, and
skips narrating the entire response. Finality must instead be read from the
send settling itself: `streamingAssistantMessageID` moving off the message
(guaranteed by `performSend`'s defer on success, error, and cancel alike),
with the marker's clearing re-triggering evaluation, since settling may not
touch `messages` at all.

Siblings of the audio-session defect: the teardown has no `sessionGeneration` guard
(a stale teardown can kill the *next* TTS session after barge-in);
`SpeechService.teardownEngine` is fire-and-forget while `startRecording`
detaches setup (the silent-retry path can dead-mic itself); the
"TTS yields to STT" sink's `stop()` teardown can kill a live inline
dictation session.

## Requirements

**Traceability:** R1 → `REQ-NAR-001`; R2 → `REQ-NAR-002` (06 §B1); R3 →
`REQ-NAR-003`; R4 → `REQ-NAR-004`; R5 → `REQ-NAR-005`; R6 → `REQ-NAR-006`;
R7 → `REQ-NAR-007` (cites 018 R1 on-device STT and `REQ-VOX-005`); R8 has no
`REQ-` ID — derived testability requirement.

**Zone declaration:** the entire loop is `.z0Device` per spec 014 R1 —
on-device STT (018 R1 interim: `requiresOnDeviceRecognition = true`),
on-device generation (017), on-device TTS (018 R7). Nothing here leaves the
device.

### R1. The loop is a conversation (`REQ-NAR-001`)

Entering Narration Mode (the composer's waveform button) starts a repeating
turn cycle that continues until the user exits:

1. **Listening** — mic open, live partial transcript shown.
2. **Auto-send** — a 1.5 s stable-transcript pause with the audio level below
   the speech floor sends the turn (`shouldAutoSend`, unchanged). The mic
   button sends immediately.
3. **Thinking** — the turn is sent through the normal chat pipeline; the
   reply streams into the transcript as a typed assistant message.
4. **Speaking** — the streaming reply is narrated per-sentence while it
   streams; the typed message remains the canonical record.
5. **Loop** — when narration drains, listening resumes automatically. There
   is no fixed turn limit; the loop ends only on exit (or unrecoverable
   error per R4).

Status affordances: "Listening…", "Thinking…", "Speaking…" (existing
`NarrationFooter` states).

### R2. Half-duplex invariant (`REQ-NAR-002`)

The loop is strictly half-duplex: never `.playAndRecord`, never
`.voiceChat`. The record session is fully released before a TTS session
activates, and the TTS session is fully released before the mic re-arms.
Full-duplex voice barge-in — and any global `AudioSessionArbiter` actor
serializing session transitions across services — is **explicitly deferred**
to the future full-duplex mode (06 §B1).

### R3. Ordered, guarded session handoff (`REQ-NAR-003`)

The TTS → STT edge must be as ordered as the STT → TTS edge already is:

- (a) `VoicePlaybackService`'s session release is an **awaitable task**
  (`waitForSessionRelease()`); `NarrationCoordinator` awaits it before
  arming the mic for the next turn.
- (b) The release is **staleness-guarded** by a pure decision
  (`shouldReleaseAudioSession`): it must not deactivate the session if the
  playback `sessionGeneration` has advanced, a recording is live, or a new
  speaking session exists.
- (c) `VoicePlaybackService` activation awaits any pending release of its
  own (TTS→TTS restart ordering).
- (d) `SpeechService.startRecording` awaits its own pending fire-and-forget
  teardown before detaching engine setup (STT→STT restart ordering).

### R4. Listening liveness and recovery (`REQ-NAR-004`)

A listening turn that produces **no** signal — no partial transcript and an
audio level pinned at exactly 0 (a live mic's smoothed RMS noise floor is
nonzero) — for 4 s is dead. Detection reuses the existing 4 Hz watchdog (no
new timers; pure decision `isListeningDead`). Recovery: cancel and silently
re-arm the mic **once** per turn (existing `didRetryListening` gate); a
second death surfaces `errorKind = .recordingFailed` with the existing
Try Again affordance. No hands-free session may hang silently.

### R5. Barge-in and exit (`REQ-NAR-005`)

- Mic tap while speaking cuts narration immediately and reopens the mic
  (tap-to-interrupt; the typed reply keeps streaming into the chat).
- Mic tap while listening sends immediately.
- Exit (X, leaving the page, backgrounding the app mid-listen) tears the
  loop down but deliberately leaves an in-flight reply streaming into the
  chat transcript.

### R6. Persistence and continuity (`REQ-NAR-006`)

Every spoken turn is a first-class chat turn: persisted through
`ChatViewModel` → `ChatService` → `LocalChatStore` into the session's own
log, indistinguishable from a typed turn, titled/listed in the history
sheet, and included in model history on later turns. Narration Mode must
work identically inside a resumed session (loaded from history) — the
narration transcript starts clean (`transcriptStartIndex`) while prior
messages stay on the chat page and in context.

### R7. Interruptions, background, privacy (`REQ-NAR-007`)

- Call/Siri/route-loss while **speaking**: pause with resume affordance
  (existing `REQ-VOX-005` behavior; lock-screen transport applies).
- Interruption while **listening**: the turn recovers via R4 (silent re-arm,
  then surfaced error) — never a silent hang.
- STT remains on-device-only (`requiresOnDeviceRecognition = true`, 018 R1
  interim); this spec adds no new audio capture, storage, or network path.

### R8. Testability (derived)

`NarrationCoordinator` accepts protocol seams
(`NarrationSpeechListening`, `NarrationVoicePlayback`) with
default-argument singletons, matching the `ChatViewModel.init(chatService:)`
convention. Ordering (R3a), liveness (R4), barge-in (R5), and loop-close
(R1.5) are unit-tested against mocks; `shouldReleaseAudioSession` and
`isListeningDead` are pure and table-tested.

## Non-goals

- Full-duplex voice barge-in (speak-over-the-agent) and voice-processing
  I/O — deferred per 06 §B1.
- A global audio-session arbiter actor — right shape for full-duplex,
  wrong risk profile for a two-edge ordering fix.
- Changing the history model — voice and typed turns share one log per
  conversation by design (user-confirmed 2026-08-17).
- Tuning `autoSendPause` / silence heuristics beyond what R4 requires.
- `SpeechAnalyzer` migration (018 R1 owns it).

## Acceptance

1. On device: a fresh chat sustains ≥ 4 consecutive hands-free turns with
   no touches — including answering the instant TTS ends (the regression).
2. Barge-in mid-speech restarts listening; the interrupted reply finishes
   streaming as text.
3. A session resumed from history sustains the loop, with prior turns
   feeding model context and no mutation of pre-existing messages.
4. Unit: loop-close resumes listening; `startRecording` is provably not
   called before `waitForSessionRelease` completes; stale teardown decision
   table; liveness decision table plus one-retry-then-error integration;
   empty-transcript turn re-listens without sending.
5. Regression: tap-to-read, inline dictation, journal dictation, and the
   settings voice preview behave unchanged.
