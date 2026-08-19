---
id: 035
title: Spoken-Form Formatter and Expression Tags
tier: P1
status: not-started
effort: 1 session
depends_on: [031]
findings: [three-text-transforms-must-compose-in-order, do-not-double-transform-numbers, expression-tag-allowlist-by-construction, breath-insertion-is-mode-specific, rate-control-already-ships]
source_refs: [REQ-TTS-008, REQ-VOX-006]
tech_refs: [technology/13-neural-tts-coreml.md, technology/06-speech-and-audio.md]
---

# 035 — Spoken-Form Formatter and Expression Tags

**Traceability:** implements `REQ-TTS-008` on the engine from
`specs/031-neural-synthesis-engine.md`. Composes with — and does not replace —
the two text transforms already shipping: `SpeechTextSanitizer` (runtime
transformer) and `SpeakabilityLinter` (build-time validator, `018` R9 /
`REQ-VOX-006`).

## Why

The synthesizer is only half of "sounds human"; the script is the other half. A
better engine makes bad script *more* obvious, not less — a compact system voice
reading "3/4" as "three slash four" sounds like a robot being a robot, and a warm
neural voice doing it sounds like a person having a stroke.

This extends an architectural rule the app already holds: every number in
user-facing prose comes from SwiftData rather than from the model. Those numbers
must also **speak** well, and display register is not spoken register. "2026-03-03"
is correct on screen and wrong out loud.

The second half of this spec is a containment problem. Expression tags
(`<breath>`, `<sigh>`) make speech feel alive, and an open tag vocabulary hands a
language model a channel into the synthesizer. The allowlist is not a filter that
runs late; it is the only thing that ever reaches the engine.

## Technology References

- `specs/reference/technology/13-neural-tts-coreml.md` §1 — the engine's text
  front end is G2P-free and NFKD-normalized (🔴, vendor claim), which is why
  numbers and currency largely need no help and over-transforming is the real
  risk.
- `specs/reference/technology/06-speech-and-audio.md` §B6 — the speakability
  contract this composes with.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | A runtime sanitizer already exists and runs at a single choke point | `MeetMemento/Utilities/SpeechTextSanitizer.swift:21` `sanitize(_:)`, `:53` `speakableText(heading1:heading2:body:)`; invoked inside `VoicePlaybackService.swift:271` `enqueue(sentence:)` | — (asset; the choke point must be preserved) |
| 2 | A build-time validator enforces the same intent from the other side | `MeetMemento/Utilities/SpeakabilityLinter.swift` — `REQ-VOX-006` hard-fail patterns, Swift port of `scripts/ci/speakability_lint.py`; CI gate `Speakability linter selftest (spec 018 R9 / REQ-VOX-006)` | — (asset) |
| 3 | Nothing converts display register to spoken register anywhere. Dates, times, and ambiguous fractions reach the synthesizer verbatim | No date/time/number spoken-form transform exists in `MeetMemento/Utilities/` | High — the gap this spec fills |
| 4 | There is no expression-tag vocabulary and no filter for one — an unbounded surface the moment a prompt is asked to produce tags | `grep -rn '<breath>\|<sigh>\|<laugh>' MeetMemento/` → zero hits | High — must be closed before tags are ever requested |
| 5 | A user-facing speech-rate control already ships, contradicting any "no rate UI" assumption | `MeetMemento/Models/SpeechRatePreset.swift` (slower/normal/brisk/fast, default `.brisk`); `PreferencesService.swift:23` `speechRate` | Medium — rate defaults must account for it |

## Requirements

**Traceability:** R1, R2 → `REQ-TTS-008` (normalization); R3 → `REQ-TTS-008`
(tags); R4 → `REQ-TTS-008` (breath insertion); R5 → `REQ-TTS-008` (rate).

**Zone declaration:** `.z0Device`. Pure local text transformation; no model call,
no network.

### R1. `SpokenFormFormatter` runs on every chunk, before synthesis (`REQ-TTS-008`)

Minimum transforms:

- **Dates** — ISO and numeric forms to spoken dates ("2026-03-03" → "March
  third").
- **Times** — 24-hour forms to spoken times.
- **Currency and units** where SwiftData injects figures.
- **Ordinal vs cardinal** selection.
- **Symbol stripping** — markdown remnants and bullet characters, as a safety net
  behind spec 032 R5's prompt contract. Prompts asking for no markdown are the
  primary control; this is the belt.

**Composition order is normative**, because three transforms now touch the same
string and the wrong order silently undoes work:

```
model output
  → chunker (032)
  → SpokenFormFormatter (this spec)     ← display register → spoken register
  → SpeechTextSanitizer (existing)      ← markdown/citation/emoji stripping
  → engine
```

The formatter runs **before** the sanitizer: it needs to see structure the
sanitizer removes, and the sanitizer must have the last word so nothing the
formatter emits can reintroduce an unspeakable character. `SpeechTextSanitizer`
stays where it is — inside `enqueue`, one choke point, serving both engines. Do
not move it, and do not add a second invocation site.

**Acceptance:** given a chunk containing an ISO date and a markdown emphasis
marker, when it reaches the engine, then the date is spoken form and the marker
is gone — with the formatter's output demonstrably passing through the sanitizer,
not around it.

### R2. Do not double-transform (`REQ-TTS-008`)

The engine handles raw numbers and currency natively. The formatter therefore
transforms **only** cases where spoken register genuinely differs from display
register — dates, times, and ambiguities like "3/4" that could be a fraction or a
date.

Over-transforming is the more likely failure and the harder one to notice: an
engine that would have said "twenty twenty-six" correctly, handed "twenty
twenty-six" as text, may produce something worse. A test corpus of tricky strings
with **expected pass-throughs** is required — cases the formatter must leave
exactly alone are as much a part of the contract as cases it must change.

**Acceptance:** given the corpus, when formatted, then every pass-through case is
byte-identical to its input — asserted individually, so a regression names the
string it broke.

### R3. Expression tags are an allowlist, enforced by construction (`REQ-TTS-008`)

The model MAY emit tags from a closed allowlist only — initially `<breath>`,
`<sigh>`, `<laugh>`. Any tag not on the list is **stripped**.

**Arbitrary tag pass-through MUST be impossible.** The implementation is a
whitelist parse — recognise known tags, discard every other angle-bracketed
construct — not a blacklist of tags to remove. A blacklist is a list of things
someone thought of, and the tag stream is generated text: it will eventually
contain something nobody thought of, including malformed and nested constructs.

Enlarging the allowlist is a spec edit, not a prompt edit. A tag vocabulary that
grows by someone adding a word to a prompt is not an allowlist.

**CI gate:** `Expression-tag allowlist (spec 035 R3 / REQ-TTS-008)` — unit-level,
failing with a message naming `REQ-TTS-008`, proven against a planted violation.

**Acceptance (Given/When/Then):**
- Given output containing `<script>`, `<custom>`, nested tags, and malformed
  fragments (`<brea`, `<>`, `< breath >`), when formatted, then all are stripped
  and only allowlisted tags survive.
- Given an allowlisted tag, when formatted, then it reaches the engine intact.
- Given a tag added to a prompt but not to the allowlist, when it appears, then
  it is stripped — the prompt cannot widen the vocabulary unilaterally.

### R4. Breath insertion is mode-specific (`REQ-TTS-008`)

`<breath>` is injected automatically at **paragraph boundaries in read-back mode
only**. Not in conversation mode, where pacing is different: a conversational turn
is short and a manufactured breath inside one reads as hesitation rather than
composure.

**Acceptance (Given/When/Then):**
- Given a three-paragraph entry read back, when formatted, then exactly **two**
  breaths are injected — boundary count, not paragraph count.
- Given the same text in conversation mode, when formatted, then **zero** breaths
  are auto-injected. Model-emitted allowlisted tags still pass through.

### R5. Rate defaults, against a control that already ships (`REQ-TTS-008`)

Defaults are read-back **0.95×** and conversation **1.0×**, exposed as named
constants — reading aloud wants a fraction more room than talking does.

These are **multipliers over the user's `SpeechRatePreset`**, not replacements for
it. The design that motivated this family assumed no user-facing rate control;
Memento ships one, with a UI test asserting its persistence (spec 033's note).
The user's preset is the base and the mode default is the adjustment, so a user
who chose "slower" gets slower in both modes and still gets read-back slightly
more measured than conversation.

No new user-facing rate UI is added.

**Acceptance:** given each `SpeechRatePreset`, when read-back and conversation
rates are computed, then read-back is 0.95× conversation for every preset, and
the user's choice is never overridden — table-tested.

## Non-goals

- Prompt authorship, including the instruction to emit expression tags — spec 017
  R8's `PromptRegistry` owns prompt text; spec 032 R5 owns the spoken-register
  contract.
- Replacing or relocating `SpeechTextSanitizer` or `SpeakabilityLinter`. Both
  stay; this composes with them.
- Emotion detection or mood-adaptive voice — out of scope per the product
  constitution (clinical-claim proximity), and not reopened here.
- SSML. The engine's text front end is not an SSML consumer; the allowlist is the
  expression surface.
- Localization of spoken forms beyond the app's current language support.

## Acceptance

1. **Unit:** a 50-string corpus — ISO dates, numeric dates, 24-hour times,
   fractions, currencies, units, markdown fragments — maps to expected spoken
   forms, **including pass-through cases asserted individually**.
2. **Unit:** injection corpus — `<script>`, `<custom>`, nested, malformed — fully
   stripped; allowlisted tags preserved.
3. **Unit:** three-paragraph read-back yields exactly two injected breaths;
   conversation mode yields zero.
4. **Unit:** rate table — read-back is 0.95× conversation across every
   `SpeechRatePreset`.
5. **Unit/integration:** composition order verified — formatter output passes
   through `SpeechTextSanitizer` before reaching the engine.
6. **CI:** `Expression-tag allowlist (spec 035 R3 / REQ-TTS-008)` live and proven
   to fail on a planted violation; the existing
   `Speakability linter selftest (spec 018 R9 / REQ-VOX-006)` still green.

## Regression Guards

- **Spec 018 R9 / `REQ-VOX-006`** — the speakability contract and its CI gate are
  untouched. This spec adds a transform; it does not relax a validator.
- **`SpeechTextSanitizer`'s single choke point** inside `enqueue` — preserved. Two
  invocation sites means one of them will eventually be bypassed.
- **CONSTITUTION rule 4** — TTS-bound text follows `REQ-VOX-006`. A neural voice
  does not make markdown speakable.
- **CONSTITUTION §2** — the utterance-session seam is unchanged.
- **Spec 033's rate control** — Speaking Speed keeps working and keeps
  persisting; its UI test must stay green.
- **Spec 029 R1** — no plaintext in logs. The formatter must not log the strings
  it transforms, which is exactly what one would reach for while debugging it.

## Appendix — interface sketch

```swift
/// Zone: .z0Device. Pure text → text. Runs per chunk, BEFORE SpeechTextSanitizer (R1).
enum SpeakingMode { case readBack, conversation }

struct SpokenFormFormatter {
    static func format(_ chunk: String, mode: SpeakingMode) -> String

    /// Closed vocabulary. Widening it is a spec edit, never a prompt edit (R3).
    static let allowedTags: Set<String> = ["breath", "sigh", "laugh"]

    /// Multipliers over the user's SpeechRatePreset — never replacements (R5).
    static let readBackRateScale = 0.95
    static let conversationRateScale = 1.00
}
```
