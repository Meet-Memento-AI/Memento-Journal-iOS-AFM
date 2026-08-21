---
id: 018
title: Capture and Voice Output
tier: P1
status: in-progress (2026-08-19) — SpeechAnalyzer + SpeechTranscriber + SpeechDetector engine; SFSpeechRecognizer remains permission-only
effort: 3 sessions
depends_on: [013, 015, 017]
findings: [sfspeechrecognizer-migration-not-carry-forward, journal-capability-not-gated-filing, weatherkit-content-free-zone, speakability-linter-ci-gate, tts-complete-text-constraint, personal-voice-verify-first, tts-vendor-rule-was-a-privacy-rule, phonemizer-gpl-contamination-gate]
source_refs: [REQ-CAP-001, REQ-CAP-002, REQ-CAP-003, REQ-CAP-004, REQ-CAP-005, REQ-CAP-006, REQ-CAP-007, REQ-CAP-008, REQ-CAP-009, REQ-CAP-010, REQ-CAP-011, REQ-CAP-012, REQ-VOX-001, REQ-VOX-002, REQ-VOX-003, REQ-VOX-004, REQ-VOX-005, REQ-VOX-006, REQ-VOX-007, REQ-TTS-001, REQ-TTS-003, REQ-TTS-009]
tech_refs: [technology/06-speech-and-audio.md, technology/08-context-frameworks.md, technology/13-neural-tts-coreml.md]
---

# 018 — Capture and Voice Output

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§8 "Capture and voice" in full.

## Why

Capture is largely a carry-forward: `SpeechAnalyzer`/`SpeechTranscriber` on-device
transcription already exists in this codebase and has no cloud fallback to delete
(the source doc's "Gemini Audio fallback" concern, `REQ-CAP-001`, does not apply
here — verify and record that during execution). What's net-new is Journaling
Suggestions (zero-privacy-cost rich context, a genuine differentiator per the
source doc), ambient context (place/weather), and the entire text-to-speech
surface — the long-term differentiator versus Slate, and the reason reflections
(spec 019) don't stream while chat does (`REQ-INT-014`, spec 017).

## Technology References

- `specs/reference/technology/06-speech-and-audio.md` — primary:
  `SpeechAnalyzer`/`SpeechTranscriber`, `AVAudioSession` durability patterns,
  `AVSpeechSynthesizer`/Personal Voice, the `SpeakabilityLinter` contract
  (`REQ-VOX-006`).
- `specs/reference/technology/08-context-frameworks.md` —
  `JournalingSuggestionsPicker`, `WeatherKit`, `CoreLocation` reduced
  accuracy for ambient-context capture.

## Current State (evidence)

Speech-to-text is already fully native/on-device:
`MeetMemento/Services/SpeechService.swift` uses Apple's `Speech` + `AVFoundation`
frameworks directly, with no Gemini Audio fallback found anywhere (confirmed
2026-07-23) — this piece may already satisfy `REQ-CAP-001`/`002`/`003`/`004`
largely as-is; verify against the requirement list rather than rebuilding. No
Journaling Suggestions, ambient context (place/weather), or any TTS integration
exists.

## Requirements

**Traceability:** R1 → `REQ-CAP-001`, `REQ-CAP-002`, `REQ-CAP-003`,
`REQ-CAP-004`, `REQ-CAP-006`; R2 → `REQ-CAP-005` (§16 item 9 / V17); R3 →
`REQ-CAP-007`; R4 → `REQ-CAP-008`, `REQ-CAP-009` (corrected per spec 013
R5(c)), `REQ-CAP-010`; R5 → no `REQ-` ID of its own — derived from
`technology/01` §6, supporting `REQ-CAP-010` and spec 016 R2; R6 →
`REQ-CAP-011`, `REQ-CAP-012`; R7 → `REQ-VOX-001`, `REQ-VOX-004`,
`REQ-VOX-005`, `REQ-VOX-007` (§16 item 8 / V18); R8 → `REQ-VOX-002`,
`REQ-VOX-003` (§16 item 7 / V6); R9 → `REQ-VOX-006`, P6; R10 → source doc
§9.1 capture exit criterion, paired with `REQ-SYS-008` (spec 020); R11 →
§16 items 7, 8, 9.

**Zone declaration (once, for the whole spec):** capture, transcription, and
TTS are `.z0Device` per spec 014 R1 — they never leave the device and work in
airplane mode (architecture §3.2). The single exception is WeatherKit in R6,
which is `.z1AppleContentFree` per 014 R1 (a real network call to Apple
carrying a location, never journal content). No operation in this spec is
`.z1AppleContent`, so **no Z1→Z0 degradation stories exist here** — the §17
degradation checklist item is satisfied vacuously, and the only capability
degradation is R5's (no-Apple-Intelligence devices skip photo descriptions).
This spec never invents its own zone tagging; every tag cites 014 R1.

### R1. Speech-to-text — `SpeechAnalyzer` migration, not a carry-forward
`REQ-CAP-001` requires `SpeechAnalyzer`/`SpeechTranscriber`, "no
`SFSpeechRecognizer`, no cloud fallback of any kind." The Current State's
"may already satisfy `REQ-CAP-001`–`004` largely as-is" was re-verified while
deriving these requirements (2026-07-24) and is **optimistic**: the no-cloud-
fallback half holds (no Gemini Audio anywhere, confirmed 2026-07-23), but
`SpeechService.swift` is built on the legacy stack `REQ-CAP-001` names as
disallowed. Audit evidence, to be re-confirmed by Task 1 before any code
changes:

| `REQ-CAP-` | Current `SpeechService.swift` state | Verdict |
|---|---|---|
| 001 | `SFSpeechRecognizer` + `SFSpeechAudioBufferRecognitionRequest` (`SpeechService.swift:56`, `:207`) — the explicitly disallowed API. `requiresOnDeviceRecognition` is **never set**, so on-device execution is not mechanically guaranteed (server-based recognition is possible for some locales). No cloud fallback of our own exists — the migration is an engine swap, not a deletion. | **Migrate** |
| 002 | No `AssetInventory` / locale-model check anywhere (legacy API didn't need one; `SpeechAnalyzer` does). | **Build** |
| 003 | Partials on (`shouldReportPartialResults = true`, `:208`) but no volatile-vs-finalized visual distinction contract. | **Half-met** |
| 004 | Audio session is `.record`/`.measurement` (`:200`–`:204`), not `.playAndRecord`/`.spokenAudio`; **no** `interruptionNotification`/`routeChangeNotification` observers — a phone call today kills the recording. Also: 10s silence auto-stop (`:29`) would truncate a reflective pause mid-entry; re-evaluate against R10's durability criterion. | **Build** |
| 006 | Hardcoded `Locale.current` (`:167`, `:281`); no user setting. | **Build** |

**Interface contract** (§17): the engine swap hides behind a protocol so the
published observable surface consumed by PRES-024/PRES-063 UI (`isRecording`,
`transcribedText`, `audioLevel`, `currentDuration`, session ownership) is
preserved while the internals are replaced:

```swift
/// Zone: .z0Device (spec 014 R1). Works in airplane mode; no network path exists.
protocol TranscriptionEngine: Sendable {
    /// REQ-CAP-002 — locale model assets via AssetInventory.
    func assetState(for locale: Locale) async -> TranscriptionAssetState
    func downloadAssets(for locale: Locale) -> AsyncStream<Progress>
    /// REQ-CAP-006 — locale from user setting, defaulting to device locale.
    func start(locale: Locale) async throws -> AsyncThrowingStream<TranscriptionUpdate, Error>
    func pause() async                    // interruption .began (REQ-CAP-004)
    func resume() async throws            // interruption .ended + .shouldResume
    func finish() async throws -> String  // finalized full transcript
}

enum TranscriptionUpdate: Equatable {
    case volatile(String)    // REQ-CAP-003: render visually distinct
    case finalized(String)
}

enum TranscriptionAssetState: Equatable {
    case installed, downloading, missing
}
```

⚠️ **Verify-first (V15, V16 — 🔴 in `technology/06` A1/A2):** the
`SpeechAnalyzer`/`SpeechTranscriber` architecture is verified (coordinator +
module + async result sequence) but exact initializer parameters, result
shapes, and the `AssetInventory` API are not. Compile-check both against the
installed SDK **before** writing engine code; the protocol above is the seam
that keeps callers unaffected by whatever the real signatures turn out to be.

**Recording state machine** (§17 — the durability flow `REQ-CAP-004` governs):

```
idle → requestingPermission → checkingAssets ──missing──→ downloadingModel
                                    │installed                  │done
                                    ▼                           ▼
                                recording ◀─────────────────────┘
recording ──interruption .began (call/Siri/alarm)──→ paused
paused ──.ended + .shouldResume──→ recording   (buffered audio preserved)
paused ──user stops / no .shouldResume──→ finalizing
recording ──stop / silence policy──→ finalizing → done | failed
(backgrounding and device lock do NOT leave `recording` — that is the point)
```

**Error taxonomy** (design copy, not developer strings — §17; final wording
owned by design):
| State | Copy (draft) |
|---|---|
| Permission denied | *"Memento needs the microphone to hear you. You can turn it on in Settings — or just type."* |
| Locale model missing (first run) | *"Getting your language ready — you can type in the meantime."* (progress shown; `technology/06` A2: this is a first-run experience requirement, not a detail) |
| Interrupted (call/Siri/alarm) | *"Paused for your call. Everything you said is safe."* |
| Recognition failed mid-entry | *"Transcription stopped, but your recording is safe."* (never discard captured audio on error) |

**Acceptance (Given/When/Then):**
- Given a recording in progress, when an interruption `.began` fires (test:
  simulated; then a real incoming call per `technology/06` A4), then state
  moves to `paused` with all finalized text and buffered audio preserved; when
  `.ended` arrives with `.shouldResume`, recording resumes; nothing captured
  before the interruption is lost.
- Given airplane mode, when a spoken entry is recorded and stopped, then the
  full transcript finalizes — the `.z0Device` proof.
- Given a first run with the locale model missing, when the user opens the
  composer, then download progress is visible and typing works immediately —
  never a silent transcription failure (`REQ-CAP-002`).
- Given volatile results streaming in, when rendered, then they are visually
  distinct (opacity/weight/color) from finalized text (`REQ-CAP-003`).
- Given the completed migration, when
  `grep -rn 'SFSpeechRecognizer' MeetMemento/` runs, then it returns no
  app-target matches (`REQ-CAP-001` as a checkable criterion).
- Given the migrated engine, when PRES-024 (editor dictation FAB) and PRES-063
  (onboarding dictation) flows run, then observable behavior is unchanged —
  the Regression Guards' preservation contract, exercised as tests.
- Transcription locale follows a user setting defaulting to device locale
  (`REQ-CAP-006`); the `Translation`-framework second-language option is
  specified but **not scheduled for 2.0** — restated as a non-goal so a
  helpful implementer doesn't add it.

### R2. Audio routes and AirPods high-quality recording — verify-first
Route awareness (built-in / wired / Bluetooth) is required regardless of any
AirPods enhancement: R1's `routeChangeNotification` observer must keep a
recording alive across a route change (`REQ-CAP-005`).

The high-quality/studio AirPods recording path is 🔴 **UNVERIFIED**
(`technology/06` A5; §16 item 9 / V17). Per this spec's rule that 🔴 claims
become verify-first criteria: **nothing may hard-depend on it.** If V17
confirms the API, Memento SHOULD prefer the high-quality route when available
and indicate the improved input in the recording UI; if V17 refutes it, the
SHOULD lapses and R2 is satisfied by standard route handling alone. Either
outcome is recorded in `technology/11-verification-queue.md` V17.

**Acceptance:**
- Given a recording in progress on built-in mic, when AirPods connect (route
  change), then the recording continues without data loss — device test.
- Given V17 confirmed, when recording starts on qualifying AirPods, then the
  high-quality route is selected and the UI indicates it; given V17 refuted,
  then no dead UI or dead code path for it exists.

### R3. Text capture is a first-class equal path
Typing is not a fallback (`REQ-CAP-007`): same `Entry` entity (spec 015 R1),
same derived-field pipeline — a typed entry flows through the identical
spec 017 R1 `reflect(on:)` call and the identical spec 016 R2 donation path,
with `source == .text`. No capture-adjacent capability (attachments,
Journaling Suggestions, ambient context, reflection, TTS of the resulting
reflections) may be voice-only.

**Acceptance:**
- Given a typed entry saved, when the pipeline runs, then title/summary/mood/
  topics/salience and index donation are produced by the same code path as a
  spoken entry — asserted by a test that runs both sources through one
  pipeline entry point, not two parallel implementations.
- Given the composer, when opened, then keyboard capture is reachable as
  directly as voice capture (no extra taps to "switch modes").

### R4. Journaling Suggestions — picker, corrected entitlement, no ghostwriting
`JournalingSuggestionsPicker` (`REQ-CAP-008`, `technology/08` §2): the system
surfaces the user's workouts, photos, music, podcasts, significant locations,
and state-of-mind logs in a **system-process picker**; Memento receives only
what the user explicitly selects. Zero privacy cost — no HealthKit read
authorization, no Photos access, no location permission, no Memento network
call. Zone: `.z0Device` (014 R1).

**Entitlement — corrected state (`REQ-CAP-009`).** The source doc's "requires
a request to Apple with review lead time — file in week 1" framing is
**superseded** by the 2026-07-23 re-research (spec 013 R5(c),
`technology/08` §2): `com.apple.developer.journal.allow` is 🟡 LIKELY a
standard Xcode-addable capability (Signing & Capabilities → "+ Capability" →
Journal, since Xcode 15.1 beta / iOS 17.2), with no discoverable request form
or approval queue — unlike PCC's genuinely gated process. It is 🟡 not ✅, so
per this spec's verify-first rule the confirmation is an explicit acceptance
criterion below, and Task 2's "confirm spec 013's entitlement filing landed
first" is satisfied by that check — there is likely **no filing to wait
for**.

**No ghostwriting (`REQ-CAP-010`).** A selected suggestion becomes an
`Attachment` (spec 015 R1's `Attachment` contract — cite, don't redefine)
plus a **seeded prompt in the composer**. It MUST NOT auto-generate entry
text: the entry body remains empty until the user types or speaks
(`technology/08` §2 Rules: "An app that writes your journal for you is not a
journal"). Suggestion content becomes searchable metadata on the entry,
flowing into spec 016 R2's donation attribute set and hydration — this spec
adds the metadata at capture; 016 owns the attribute schema.

**Acceptance (Given/When/Then):**
- ⚠️ **Verify-first:** open Xcode → target → Signing & Capabilities →
  "+ Capability" → search "Journal". If addable directly, record ✅ in
  `technology/11-verification-queue.md` V3 and drop the scheduling-dependency
  framing entirely; if Xcode surfaces a request/approval flow instead,
  re-flag 🔴 and file it per spec 013 R5(c). This check runs **before**
  Task 2's implementation starts.
- Given the picker completes with a selection, when the composer returns,
  then an `Attachment` is persisted, a seeded prompt is visible, and the
  entry body is empty — and stays empty until user input.
- Given the picker is dismissed without a selection, when the composer
  returns, then nothing was received or persisted.
- Given an entry with a suggestion attachment, when spec 016's hydration runs
  for it, then the suggestion-derived metadata is present in the returned
  attribute set.

### R5. Photo attachments — Z0-only on-device descriptions as metadata
Photo attachments (whether picked via a Journaling Suggestion or added
directly) get an on-device generated description that becomes searchable
metadata on the entry, feeding spec 016 R2's attribute set. Vision input to
the on-device model is ✅ verified (`technology/01` §6); **images are never
sent to PCC** — spec 017 R2's router row makes image understanding Z0-only
with structurally no Z1 path, and this spec cites that contract rather than
re-enforcing it. Description generation goes through spec 017's
`IntelligenceService` (it is a generation, so 017's single-importer boundary
applies); this spec owns invoking it at attachment time and persisting the
result.

**Acceptance:**
- Given a photo attached on an Apple Intelligence device, when the entry is
  saved, then a description string is persisted and appears in the donated
  attribute set (016 R2's hydration test extended with a photo fixture).
- Given a device without Apple Intelligence, when a photo is attached, then
  the attachment works and the description is skipped silently — attachment
  capability never gates on the model.
- No code path in this spec touches PCC for images — guaranteed by 017 R2's
  router acceptance test, cited not duplicated.

### R6. Ambient context — place and weather, off by default, Z0-summarized
At capture time, with permission (`REQ-CAP-011`): a coarse place name from
`CoreLocation` **reduced accuracy**, reverse-geocoded **on-device** via
MapKit, stored as a short string — never coordinates (`technology/08` §5).
Zone: `.z0Device`. And `WeatherKit` conditions stored as a short string —
a real network call to Apple carrying a location and never journal content,
therefore `.z1AppleContentFree` per spec 014 R1 (the concrete case that enum
case exists for); it is classified as such in 014 R4's
`NetworkCallSiteAudit`, disclosed in the privacy explainer, and controlled by
an explicit setting that is **off by default**.

Rules (`REQ-CAP-012` + `technology/08` §6, all normative here):
1. Every source is optional, off until granted, and excludable per-entry and
   globally.
2. Correlation language only, never causal — "you often write about feeling
   low on days you slept badly," never mechanism claims. (Chart n-visibility,
   `REQ-SUR-001`, is spec 019's.)
3. **Z0-only summarization rule:** ambient context is a Z0 input by default —
   summarized on-device before anything derived from it approaches a Z1
   prompt. Which prompts include the summarized result is spec 017's routing
   and prompt-registry business; this spec's obligation is that raw ambient
   values never appear in a Z1 prompt payload.
4. Ask late, in context — weather permission at first Patterns-view open, not
   onboarding; declining is costless.

**Acceptance (Given/When/Then):**
- Given a fresh install, when defaults are inspected, then place and weather
  capture are both off, and no `WeatherService` call occurs before explicit
  grant — asserted by network-audit test, consistent with 014 R4.
- Given ambient context captured on an entry, when the user excludes it
  per-entry, then the strings are removed from the entry and its donated
  attributes; given the global toggle off, then no new capture occurs.
- Given persisted ambient context, when storage is inspected, then it is
  short strings only — no coordinates anywhere (`technology/08` §5).
- Given any Z1 prompt payload containing ambient-derived material, when
  inspected in 017's tests, then it contains only Z0-computed summaries,
  never raw place/weather values.

### R7. TTS rendering — synthesis is on-device, not single-vendor; cache and audio-app behavior
Every `Reflection` MUST be renderable as audio. Zone: `.z0Device`.

**The rule, restated (amended 2026-08-18 — `REQ-TTS-001`):** *TTS synthesis MUST
execute entirely on-device. The TTS path MUST make zero network calls at
synthesis time, model-load time, or voice-selection time. Third-party engines are
permitted where fully local, license-cleared per the dependency allowlist
(`REQ-MON-005`, and see R12), and free of network egress. Cloud or hybrid TTS
remains forbidden.* This replaces the vendor-shaped phrasing that stood here
before — "no third-party streaming TTS SDK, ever" was a privacy rule wearing a
vendor rule's clothes, and it forbade the one class of engine that satisfies the
privacy rule completely. What the product actually cares about is that no word of
a user's journal crosses a network to be spoken. Specs `030`–`036` own the
resulting neural-voice path; this requirement now owns the boundary rule and the
fallback.

**The `AVSpeechSynthesizer` path (`REQ-VOX-001`, `technology/06` B2) remains
permanently** as the degradation target (`REQ-TTS-003`) — it is what makes the
app work on a fresh install in airplane mode before any model asset exists. When
it is serving, it MUST still resolve the best available **Enhanced or Premium**
system voice and never degrade silently to a compact robotic one
(`VoicePlaybackService.bestVoiceIdentifier(from:currentLanguage:)` already
implements this ranking — cited, not redesigned). What changed on 2026-08-18 is
that this is no longer a *user-facing* voice choice: per `DEC-011`, spec `033`
replaces the Settings picker with the neural catalog, and the system voice
becomes an invisible fallback rather than a menu.

**The load-bearing constraint** (`technology/06` B1, ✅ VERIFIED against iOS 27.0
SDK): the synthesizer cannot consume a token stream — it needs complete text.
That is why reflections arrive complete while chat streams (`REQ-INT-014`, spec
017 R6 — cited, not re-decided here). Reflection surfaces remain the primary TTS
home; **chat additionally offers post-stream, per-message playback** (amended
2026-08-16: early validation of the voice-output pillar ahead of reflection
surfaces shipping). The complete-text constraint is upheld, not waived — chat
playback is only offered once a message's stream has ended (the action bar,
speak button included, is gated on `!isStreaming`); mid-stream playback on this
path remains forbidden.

**Scope correction (2026-08-18):** the constraint is a property of
`AVSpeechSynthesizer`, not of speech synthesis — the SDK evidence in
`technology/06` B1 is entirely about `AVSpeechUtterance` initializers. An engine
that accepts arbitrary text per call is not bound by it and may be driven
chunk-by-chunk from a live stream; spec `032` owns that pipeline. Two paths, two
rules: system voice waits for the full message, neural voice does not.
Chat playback is `.z0Device`, synthesized on demand via
`VoicePlaybackService` and **not cached** (`REQ-VOX-004` caching remains
reflection-only); chat prose is markdown-bearing by design, so it passes
through a runtime `SpeechTextSanitizer` before synthesis — a transformer,
distinct from R9's speakable-by-construction contract for reflection prose.
Playback yields to capture: starting any dictation stops chat playback, and
playback never activates while `SpeechService` is recording.

**Amended 2026-08-16 (second chat amendment):** `REQ-VOX-005`'s lock-screen
and background behavior now covers chat playback too. The `audio` background
mode keeps an in-progress read alive when the app backgrounds or the device
locks; `MPNowPlayingInfoCenter` carries the speaking message's heading (no
duration or elapsed time — `AVSpeechSynthesizer` exposes no natural duration,
and an estimated scrubber would lie); `MPRemoteCommandCenter` play / pause /
toggle / stop drive `VoicePlaybackService`. The audio session deactivates when
the utterance queue drains, so no silent background session is ever held.
In-app, the speak button is pause/resume-only (tap pauses at the current word,
tap resumes); hard stop lives on the lock screen and in the implicit paths
(dictation start, regenerate, another message's playback). Voice selection and
speaking rate are user preferences (`selectedVoiceIdentifier`, `speechRate`),
surfaced in Settings → Read Aloud with the Enhanced/Premium download path per
this requirement's acceptance criteria; interruptions pause and — when the
system signals `.shouldResume` — resume in place. AirPlay/CarPlay validation
and render caching remain reflection-only. This satisfies "a play button
without lock-screen presence is a half-built feature" for chat.

- **Caching (`REQ-VOX-004`) — verdict 2026-08-18: do not build it.** The design
  was: render once to an audio file, reference it via `Reflection.audioAssetID`
  (spec 015 R1's field), invalidate on voice change. It was never implemented,
  and the neural path removes its premise — synthesis at the target real-time
  factor produces audio faster than the cache saves, while a cache invalidated
  on every voice change is cold exactly when a user is trying voices out. The
  cost was never the synthesis; it was the model load, and `031` R3's warm-up
  addresses that directly. **`REQ-VOX-004` is retired**, `Reflection.audioAssetID`
  is not to be populated, and any future revival must first show a measurement
  that a warm engine is too slow — not an assumption that it is. If it is
  revived, storage, protection class, and five-store deletion remain 015 R5/R6's.
- **Audio-app behavior (`REQ-VOX-005`):** background-audio capability,
  lock-screen controls via `MPRemoteCommandCenter`, `MPNowPlayingInfoCenter`
  metadata (title, date, duration), AirPlay, CarPlay-safe session
  configuration, correct ducking. A play button without lock-screen presence
  is a half-built feature (`technology/06` B5).
  **Duration unblocked (2026-08-18):** the standing exception — no duration or
  elapsed time, because "an estimated scrubber would lie" — was a consequence of
  `AVSpeechSynthesizer` exposing no natural duration. A rendered PCM buffer's
  frame count over its sample rate *is* the duration, exactly, so on the neural
  path the honest scrubber this requirement always wanted becomes buildable
  (`technology/13` §4). Not required by `030`–`036`; recorded here so it is
  claimed by this bullet rather than rediscovered later. The system-voice
  fallback keeps the no-duration behavior — there, the old reasoning still holds.
- **Reuse ledger (ATTACH-05, updated 2026-08-16):** the orphaned
  `NarrateButton`/`ListeningPanel` components were consciously superseded by
  the composer rework (`DictationWaveform` replaced `ListeningDotsView`; the
  files are deleted). They were voice-*input* UI and contained no synthesis
  code; nothing from them carries into playback. Chat playback's claimed
  items are now `VoicePlaybackService` and `SpeechTextSanitizer`.

**Interface contract and state machine** (§17):

```swift
/// Zone: .z0Device (spec 014 R1). Synthesis and playback never leave the device.
protocol ReflectionAudioRenderer: Sendable {
    /// Complete text in, cached file out. REQ-VOX-001/004.
    func render(_ reflection: PeriodReflection, voice: SelectedVoice) async throws -> AudioAssetID
    func invalidate(for reflectionID: UUID) async   // on voice change
}
```

```
notRendered → rendering → cached
cached → playing ⇄ paused → stopped → cached
voice selection changed: cached → notRendered   (REQ-VOX-004 invalidation)
render failure: rendering → failed  (reflection stays readable — audio is
                                     additive, never a gate on reading)
```

**`REQ-VOX-007` / §16 item 8 / V18 — verify-first, Xcode-27-gated:** whether
iOS 27 shipped any synthesis API beyond `AVSpeechSynthesizer`. WWDC26 review
surfaced none; the assumption is none shipped. This design commits to
`AVSpeechSynthesizer`; if the Xcode 27 SDK (**installed 2026-07-26**) reveals a
newer — especially streaming-capable — API, that finding would revisit the
chat/reflection split and is recorded in V18 first, not preempted here.

**Acceptance (Given/When/Then):**
- Given a weekly reflection opened, when audio is requested, then playback is
  available within 5 seconds (source doc §9.3 exit criterion), in airplane
  mode.
- Given any TTS path — system voice or neural — when synthesis, model load, and
  voice selection are exercised behind a capturing proxy, then **zero outbound
  requests** originate from TTS code (`REQ-TTS-001`; the archived artifact is
  spec 036's).
- Given the neural assets are absent, corrupt, or mid-download, when a read-aloud
  or narration turn is requested, then speech is produced by the
  `AVSpeechSynthesizer` fallback on the best available Enhanced/Premium voice —
  no hang, no error dialog, no silence (`REQ-TTS-003`).
  *(Superseded 2026-08-18: the two cache-hit / cache-invalidation criteria that
  stood here are retired with `REQ-VOX-004`.)*
- Given playback started and the device locked, when the lock screen is
  inspected, then transport controls and Now Playing metadata (title, date,
  duration) are present and functional — real-device check.
- Given no Enhanced/Premium voice downloaded **and the neural assets absent**,
  when playback runs, then it uses the best available system voice rather than
  failing — and the user is not asked to go download a system voice, because
  per `DEC-011` system voices are no longer a choice they make (spec 033 owns
  what the picker says while assets are pending; the old Settings download-help
  copy is retired with the picker).
- Given a completed assistant chat message, when Read Aloud is tapped, then
  playback uses the user's selected voice — neural when assets are ready, the
  best system voice otherwise — exactly one message speaks at a time, and
  starting dictation stops playback (chat amendment 2026-08-16, voice source
  amended 2026-08-18).

### R8. Personal Voice — delighter tier, verify posture before building
`REQ-VOX-002`: request authorization via
`AVSpeechSynthesizer.requestPersonalVoiceAuthorization()`; when granted,
enumerate voices with `voiceTraits.contains(.isPersonalVoice)` and offer them
for reflection playback. Generation is fully on-device — `.z0Device`.

`REQ-VOX-003` product rules (normative, `technology/06` B3):
1. Delighter tier — never a default, never a gate, never monetization bait.
2. Onboarding MUST NOT mention it.
3. Discovered late, at demonstrated engagement: surfaced only after the
   user's third or fourth weekly reflection (Task 5's trigger).
4. Everyone else gets Enhanced/Premium system voices (R7).

⚠️ **Verify-first — §16 item 7 / V6, 🔴:** Personal Voice was introduced as
an accessibility feature; App Review's posture on non-accessibility use in a
journaling app is unverified and is "a real risk, not a formality"
(`technology/06` B3 rule 4). **The flow is not built until V6 is closed** —
unblocked by App Review guideline research / a developer-support inquiry,
plus a real-device authorization test. This is not Xcode-27-gated; it can and
should be closed before Task 5 starts.

**Acceptance (Given/When/Then):**
- Given onboarding, when its strings and screens are audited, then Personal
  Voice appears nowhere — checkable by grep over onboarding surfaces plus UI
  test.
- Given a user with fewer than three viewed weekly reflections, when surfaces
  render, then no Personal Voice discovery affordance exists; given the
  third–fourth viewed weekly reflection, then the discovery moment may fire
  once.
- Given authorization denied or no trained voice, when reflection playback
  runs, then Enhanced/Premium voices serve with zero nagging and no repeated
  prompts.
- Given V6 still open, when Task 5 would start, then it is blocked — the
  V-queue entry must record the verified posture (with source) first.

### R9. `SpeakabilityLinter` — P6 as a build failure, not a style guide
P6 ("speakable by construction") enforced mechanically, in the style of
spec 014 R3's forbidden-phrase lint: a checkable CI criterion, not a policy
page. Every prompt producing user-facing prose forbids the patterns below
(the prompt text lives in spec 017 R8's `PromptRegistry` — 017 owns the
prompts, this spec owns the linter; 017's Out of Scope routes here), and the
linter enforces the same list against actual generations (`REQ-VOX-006`).

**Interface contract and forbidden-pattern list** (`technology/06` B6 —
normative, concrete):

```swift
struct SpeakabilityLinter {
    /// Throws SpeakabilityViolation naming the pattern and offending range.
    static func validate(_ text: String) throws
}
```

Rejected, hard-fail: markdown of any kind (`#` headings, `*`/`_` emphasis,
backticks); list markers at line start (`-`, `*`, `•`, `1.`); emoji (scalar
ranges); `http(s)://` URLs; more than one consecutive blank line (`\n\n`
runs). Rejected against generations, with a small documented allowlist
(years, clock times): parentheticals (they break spoken cadence) and
digits where words read better ("three," not "3" — heuristic: standalone
integers zero through ten).

**Enforcement:** unit tests cover each pattern with fixtures; a CI job runs
the linter over fixture-corpus generations (spec 013 R4 corpus, produced via
spec 022's harness) of every prose-producing prompt — `PeriodReflection.body`
and `.observation` at minimum — and **violations fail the build**.

> **Partial — landed 2026-08-02:** the forbidden-pattern engine + per-pattern
> test suite is implemented and wired (`scripts/ci/speakability_lint.py`,
> `.github/workflows/spec-gates.yml`). `--selftest` covers one fixture per
> hard-fail pattern (markdown headings, emphasis/backticks, list markers, URLs,
> emoji, blank-line runs) plus clean/allowlist fixtures (years, clock times);
> green, and verified to fail on a planted bad generation. Two pieces remain:
> (a) the in-app Swift `SpeakabilityLinter.validate(_:)` wrapper (a thin port of
> these rules, lands with 017's Swift code), and (b) wiring the linter over
> real fixture-corpus generations once spec 022's harness produces them.
Retrofitting speakability after prompt tuning is a rewrite of every prompt,
which is why this lands with the first prompt, not after.

**Acceptance:**
- `SpeakabilityLinter` exists with a per-pattern unit test suite (one fixture
  per forbidden pattern, plus allowlist cases that must pass).
- Given a fixture-corpus generation containing any hard-fail pattern, when
  the CI job runs, then the build fails with a message naming the pattern and
  `REQ-VOX-006` — not a generic test failure.
- Given every prose prompt in 017's registry, when reviewed, then it states
  the speakability prohibitions — review criterion coordinated with 017 R8.

### R10. Capture durability exit criterion — landed as a pair with spec 020
Source doc §9.1's exit criterion, as Given/When/Then (§17):

- **Given** a device in airplane mode, **when** a two-minute spoken entry
  endures an incoming phone call, an app switch, and a device lock during
  recording, **then** the entry appears fully transcribed with title,
  summary, mood, topics, and index donation complete — derived fields via
  spec 017's pipeline, donation via spec 016's, both running Z0.

This is an end-to-end criterion crossing three specs; this spec owns the
capture/durability half (R1's interruption handling is its mechanism). The
recording **Live Activity** (`REQ-SYS-008`, spec 020) is the designed
mitigation for silent audio loss when the user leaves the app mid-recording —
so this durability contract and 020's Live Activity MUST land as a pair:
neither ships alone, and the §9.1 run below is not green until both exist.
(The §9.1 composer-open-latency figure belongs to spec 019's capture surface,
not here.)

**Acceptance:** the scripted real-device run in Verification (call yourself,
switch apps, lock the device, all mid-recording, in airplane mode), plus R1's
automated interruption tests as the regression-proof subset.

### R11. This spec's §16 verification-queue ownership
This spec owns source doc §16 items 7, 8, and 9 — all **outstanding**:

- **Item 7 → V6** (Personal Voice App Review posture, 🔴): outstanding.
  Unblocked by App Review guideline research / developer-support inquiry plus
  a real-device authorization test — not Xcode-gated; close before Task 5
  (R8).
- **Item 8 → V18** (any iOS 27 synthesis API beyond `AVSpeechSynthesizer`):
  outstanding, assumption "none shipped" stands. Unblocked by installing the
  **Xcode 27 beta (not currently installed)** and diffing the Speech/
  AVFoundation synthesis surface (R7).
- **Item 9 → V17** (AirPods high-quality recording API and hardware
  minimums, 🔴): outstanding. Unblocked by API documentation research plus a
  device test with qualifying AirPods; R2's design holds under either answer.

Adjacent but not §16-numbered: **V15/V16** (`SpeechAnalyzer` initializers,
`AssetInventory` API — 🔴 in `technology/06` A1/A2) are this spec's to close
via compile-check against the installed SDK before R1's engine code is
written. §16 item 6 (Journaling Suggestions entitlement) remains **spec 013
R5's** item, already researched and corrected 2026-07-23; this spec merely
executes the confirming one-click Xcode check (R4) and records the result in
V3. §16 item 5 (PCC application) is spec 013's and does not concern this
spec.

**Acceptance:** V6, V17, V18 (and V15/V16) entries in
`technology/11-verification-queue.md` updated — closed with findings, or
still-open with what was attempted — before this spec's status moves to done.

### R12. Text-front-end licensing — the gate no one thinks to check (`REQ-TTS-009`)
*Added 2026-08-18 alongside R7's rewrite. R7 opened the door to local
third-party engines; this is the lock on it.*

**No GPL or GPL-contaminated component may appear anywhere in the text-processing
(G2P / phonemizer / normalizer) path of any TTS engine shipped in this app.** Any
candidate engine MUST document its **full text-front-end dependency chain**
before it enters evaluation — not after a prototype exists and the sunk cost
starts arguing.

This is a real trap, not a hypothetical one. espeak-ng is **GPL-3**, and it sits
inside the grapheme-to-phoneme path of Kokoro, sherpa-onnx, and Piper alike. The
contamination is invisible from the top of the dependency tree: it lives two
levels down, inside a component nobody classifies as "the model," in an app that
is otherwise closed-source. An engine qualifies here only by being **G2P-free**
or by having a demonstrably permissive front end — the property is structural,
and it is the single most load-bearing reason a given engine is admissible
(`technology/13` §7).

Model **weights** are governed separately from code. Where a weight license
carries an attribution condition, **the attribution ships in the app** — it is a
license term, not a courtesy (`DEC-010`; spec `030` owns the Acknowledgments
screen, which does not exist today). Where a weight license carries use-based
restrictions, those restrictions are reviewed against what the app actually does
and the verdict is written down; any future feature that lets a user generate
audio in **someone else's** voice re-opens that review from scratch.

**Zone:** unchanged — `.z0Device`. Licensing does not move data; it decides what
may run.

**Acceptance (Given/When/Then):**
- Given the shipped dependency tree, when it is scanned in CI, then no GPL-family
  license text and no espeak/phonemizer component appears in any TTS path — the
  gate fails naming `REQ-TTS-009` and this requirement, and is demonstrated once
  against a planted violation.
- Given a candidate TTS engine proposed in future, when it is evaluated, then its
  full text-front-end dependency chain is recorded in its spec **before** any
  integration commit — absence of the record blocks the evaluation, not the merge.
- Given weights whose license requires attribution, when the app ships, then the
  attribution string is present in Settings → Acknowledgments and is reachable in
  a UI test.

## Out of Scope

- The reflection generation that populates title/summary/mood/topics — spec 017
  (this spec captures and transcribes; 017 generates the derived fields).
- Weekly/monthly reflection surfaces that consume TTS — spec 019 (this spec
  defines the TTS capability; 019 wires it into specific surfaces).
- Watch capture — deferred to 2.1 per `DEC-005` (spec 020), though this spec's
  data-layer assumptions should not preclude it later.

## Tasks
- [ ] 1. Audit `SpeechService.swift` against `REQ-CAP-001`–`007`; record gaps.
- [ ] 2. Implement Journaling Suggestions integration (`REQ-CAP-008`–`010`) —
      confirm spec 013's entitlement filing (R5) landed first.
- [ ] 3. Implement ambient context capture (`REQ-CAP-011`–`012`).
- [ ] 4. Implement TTS rendering for reflections (`REQ-VOX-001`, `REQ-VOX-004`,
      `REQ-VOX-005`).
- [ ] 5. Implement Personal Voice as a delighter-tier feature, discovered after
      3rd–4th weekly reflection, never in onboarding (`REQ-VOX-002`, `REQ-VOX-003`).
- [ ] 6. Implement `SpeakabilityLinter` and wire it into the test suite
      (`REQ-VOX-006`).
- [ ] 7. ⚠️ VERIFY items 7 (Personal Voice third-party rules), 8 (any newer iOS 27
      synthesis API), 9 (AirPods high-quality recording API and hardware minimums —
      the only §16 item about AirPods; item 5 is the PCC application process,
      owned by spec 013, not AirPods).

## Verification
- [ ] **§9.1 capture exit criterion, end-to-end on a real device in airplane
      mode** (R10): start a two-minute spoken entry; mid-recording, receive a
      phone call (call yourself), switch apps, and lock the device; confirm
      the entry finishes fully transcribed with title, summary, mood, topics,
      and index donation complete — with spec 020's recording Live Activity
      (`REQ-SYS-008`) present during the out-of-app portion. Not green until
      both specs' halves exist (landed as a pair).
- [ ] Task 1 audit recorded in this spec: R1's per-`REQ-CAP-` verdict table
      re-confirmed against current `SpeechService.swift` before any code
      change; after migration, `grep -rn 'SFSpeechRecognizer' MeetMemento/`
      returns no app-target matches, and PRES-024/PRES-063 dictation flows
      behave identically (R1).
- [ ] Interruption tests pass: simulated `.began`/`.ended + .shouldResume`
      unit tests preserve buffered audio and finalized text; route-change
      mid-recording loses nothing (R1, R2) — plus the real-device call test.
- [ ] First-run locale-model UX verified on a device without the model
      installed: visible download progress, typing available meanwhile, no
      silent failure (`REQ-CAP-002`, R1).
- [ ] V15/V16 compile-check done: `SpeechAnalyzer`/`SpeechTranscriber`
      initializers and `AssetInventory` API confirmed against the installed
      SDK before engine code was written; V-queue entries updated (R1, R11).
- [ ] **Journaling Suggestions capability check recorded** (R4): Xcode →
      Signing & Capabilities → "+ Capability" → "Journal" result documented
      here and in V3 — either ✅ addable directly (scheduling dependency
      dropped) or 🔴 re-flagged with the actual request flow filed per spec
      013 R5(c).
- [ ] Suggestion tests pass: picker selection → persisted `Attachment` +
      seeded composer prompt + **empty entry body**; dismissal → nothing
      received; suggestion metadata present in spec 016 hydration output (R4).
- [ ] Photo-description tests pass: description persisted and donated on
      Apple Intelligence devices; attachment works, description skipped, on
      devices without; no PCC image path (cites 017 R2's router test) (R5).
- [ ] Ambient-context tests pass: fresh-install defaults off for place and
      weather; no `WeatherService` call before grant (network-audit test,
      consistent with 014 R4's classification of WeatherKit as
      `.z1AppleContentFree`); per-entry and global exclusion remove the
      strings from entry and donation; strings-only storage, no coordinates;
      no raw ambient values in any Z1 prompt payload (R6).
- [ ] **`SpeakabilityLinter` wired into CI and passing**: per-pattern unit
      tests green; the CI job runs the linter over fixture-corpus generations
      (spec 013 R4 corpus via spec 022's harness) of `PeriodReflection.body`/
      `.observation`, and a seeded violation fixture demonstrably **fails the
      build** with a message naming `REQ-VOX-006` (R9).
- [ ] TTS tests pass: weekly-reflection audio available within 5 seconds of
      opening, in airplane mode; replay is a cache hit (no re-synthesis);
      voice change invalidates and re-renders; lock-screen transport controls
      and Now Playing metadata verified on a real device; `NarrateButton`/
      `ListeningPanel` adopted or superseded, not duplicated (R7).
- [ ] Personal Voice posture: onboarding grep + UI test show zero mention;
      discovery affordance absent before the third viewed weekly reflection;
      denied/untrained falls back to Enhanced/Premium with no re-prompting
      (R8).
- [ ] **Source doc §16 item 7** (→ V6, Personal Voice App Review posture):
      **outstanding** — unblocked by App Review guideline research /
      developer-support inquiry plus a real-device authorization test; MUST
      be closed before Task 5's flow is built (R8, R11).
- [ ] **Source doc §16 item 8** (→ V18, iOS 27 synthesis API beyond
      `AVSpeechSynthesizer`): **outstanding** — assumption "none shipped"
      stands; unblocked by installing the Xcode 27 beta (not currently
      installed) and diffing the synthesis API surface (R7, R11).
- [ ] **Source doc §16 item 9** (→ V17, AirPods high-quality recording API
      and hardware minimums): **outstanding** — unblocked by API research
      plus a device test with qualifying AirPods; R2 holds under either
      answer. (§16 item 5, the PCC application process, is spec 013's — it
      doesn't concern AirPods.)

## Regression Guards
`CONSTITUTION.md` §4 rule 4 (Typography tokens + `REQ-VOX-006` speakability) is
enforced here. Existing `SpeechService.swift` behavior (already on-device,
already interruption-aware per whatever its current state is) must not regress
while being brought into full `REQ-CAP-*` compliance — re-verify via the audit in
Task 1 before changing it. Preservation contract: PRES-024 (editor dictation FAB
behaviors — expand-to-duration, red stop, permission alerts) and PRES-063
(onboarding voice dictation) are continuously-live invariants this spec's
`SpeechAnalyzer` migration must keep intact; the orphaned `NarrateButton`/
`ListeningPanel` components are this spec's claimed items in the contract's §4
reuse ledger (ATTACH-05) — adopt or consciously supersede them when building TTS
playback, don't rebuild in parallel.
