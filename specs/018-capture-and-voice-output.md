---
id: 018
title: Capture and Voice Output
tier: P1
status: not-started
effort: 3 sessions
depends_on: [013, 015, 017]
findings: []
source_refs: [REQ-CAP-001, REQ-CAP-002, REQ-CAP-003, REQ-CAP-004, REQ-CAP-005, REQ-CAP-006, REQ-CAP-007, REQ-CAP-008, REQ-CAP-009, REQ-CAP-010, REQ-CAP-011, REQ-CAP-012, REQ-VOX-001, REQ-VOX-002, REQ-VOX-003, REQ-VOX-004, REQ-VOX-005, REQ-VOX-006, REQ-VOX-007]
tech_refs: [technology/06-speech-and-audio.md, technology/08-context-frameworks.md]
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

- [ ] TODO (derive from source doc §8, per its §17 checklist): audit
  `SpeechService.swift` against `REQ-CAP-001`–`007` and record what's already
  compliant vs. what needs work (interruption handling, AirPods route awareness —
  ⚠️ VERIFY item 9); interface contract for Journaling Suggestions integration
  (`REQ-CAP-008`–`010`) — ⚠️ VERIFY item 6, file the entitlement request via spec
  013 in week 1, this is a scheduling dependency; ambient context capture
  (`REQ-CAP-011`–`012`, place/weather, correlation-only framing); full TTS
  interface contract (`AVSpeechSynthesizer` + Personal Voice per `REQ-VOX-001`–
  `005`) — ⚠️ VERIFY items 7, 8; the `SpeakabilityLinter` test contract
  (`REQ-VOX-006`) with concrete forbidden-pattern list (markdown, bullets,
  headings, emoji, `\n\n` runs — plus parentheticals and digits-where-words-
  read-better per `technology/06` B6, enforced against fixture-corpus
  generations as a build failure); Given/When/Then acceptance criteria for the
  capture exit criterion in source doc §9.1 (two-minute entry survives call/
  switch/lock, fully transcribed with title/summary/mood/topics/index-donation
  complete, in airplane mode) — the recording Live Activity (`REQ-SYS-008`,
  spec 020) is the designed mitigation for silent audio loss when the user
  leaves the app mid-recording, so this spec's durability contract and 020's
  Live Activity must land as a pair, not independently; photo attachments get a
  **Z0-only on-device generated description** that becomes searchable metadata
  on the entry (`technology/01` §6 — vision input is verified; images are
  never sent to PCC), feeding spec 016's donation attribute set.

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
- [ ] TODO — derive concrete test/review steps once Requirements are written;
      must include the source doc §9.1 capture exit criterion run end-to-end in
      airplane mode, `SpeakabilityLinter` passing in CI, and items 7, 8, 9 of
      the source doc's §16 verification queue each marked confirmed or
      outstanding (item 5, PCC application process, is spec 013's, not this
      spec's — it doesn't concern AirPods).

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
