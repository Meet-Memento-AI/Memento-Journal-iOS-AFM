---
id: 058
title: AFM Guidance Alignment — Plain-Prose Prompts, Swift-Held Recipe, Device-Only Ask
tier: P1
status: in-progress (2026-09-28 — R1–R6 code landed; device convo-sim run pending)
effort: 1 session plus one device convo-sim run
depends_on: [014, 017, 039, 050, 051, 055]
findings:
  - ask-defaults-to-private-cloud-compute-once-the-sdk-allows-it
  - tier-inferred-while-the-sdk-reports-it
  - bracketed-tags-echoed-as-output-format
  - marker-grammar-taught-on-turns-with-nothing-to-place
  - no-role-or-domain-permission
  - say-exactly-transcribed-in-second-person
  - one-question-rule-stated-often-and-still-broken
  - no-locale-hint
source_refs: [REQ-PRIV-001, REQ-INT-001, REQ-PRM-001, REQ-PRM-004]
tech_refs: [technology/01-foundation-models.md]
---

# 058 — AFM Guidance Alignment

**Traceability:** brings the Ask harness in line with Apple's on-device
prompting guidance for the iOS 27 Foundation Models framework. Amends spec
[`017`](017-intelligence-boundary-and-prompt-architecture.md) R2 (the Ask
routing row), closes spec [`051`](051-on-device-model-tier.md)'s R0 question
(the SDK reports the model; it does not let an app choose it), and removes
the source of spec `055`'s phantom markers. Privacy stays spec
[`014`](014-privacy-model-and-trust-boundary.md): nothing here moves content
off the device, and R1 makes that the default in code, not only in practice.

**Does not implement:** a structured `AskAnswer` schema (Meet / Moment / Sit /
Question fields), `DynamicProfile` sessions, enabling Private Cloud Compute,
a model-based turn classifier, ambient entry summaries, moving the Core
Advanced budget clamps, `includeSchemaInPrompt: false`, or response-cap
changes. Each needs a device measurement or a product decision first — see
Follow-ups.

## Why

- **Privacy default.** The Ask row routed to Z1 (Private Cloud Compute) by
  default, and the Settings switch "On-Device Only" defaults to off. Today
  the SDK has no PCC leg, so nothing leaves the device — but the day it does,
  journal conversation would go off-device unless the person had found the
  switch. That is opt-out; Memento's promise is opt-in.
- **Tier.** Spec 051 inferred the on-device model from OS and memory. The iOS
  27 SDK exposes `SystemLanguageModel.variant` (`.core3`,
  `.coreAdvanced3`), so the tier can be reported instead of guessed.
- **Tag syntax.** Every per-turn line was a bracketed tag (`[Turn: …]`,
  `[Shape: …]`, `[Evidence]`, `[Name: …]`, `[Move: …]`, `[Today: …]`). Study
  VI saw `[Evidence]` echoed into replies 25 times: the model reads tag
  syntax as output format.
- **Marker grammar.** The core taught `{{quote:N}}` / `{{date:N}}` on every
  turn, including turns with nothing to place. Study IV: removing the
  none-note while the grammar stayed in the core raised phantom markers
  from 18.4% to 25.7%. The grammar is the cause; the note was a patch.
- **Role.** The core never said what Memento is for, and never said grief,
  anger, or health are in bounds, so the guardrail-shaped model had no
  reason not to steer away from them.
- **Transcription.** Told to "say exactly \"I can't find an entry that
  supports that.\"" under a second-person core, the model wrote "You can't
  find an entry…".
- **Recipe.** "Exactly one question" and the report-opener ban were stated
  in the core, the stance line, the shape overlay, the move cue, and the
  `@Guide`, and were still broken. Sit "names a pattern", which invites the
  interpretation the core forbids.
- **Locale.** Apple's multilingual hint was missing.

## Requirements

### R1 — Ask is device-only; off-device processing needs explicit consent

- `ModelRouter`'s `.ask` row is `defaultZone: .z0Device, degradedZone: nil`
  under every PCC capability.
- `PreferencesService.allowsOffDeviceProcessing` is true only when
  "On-Device Only" is off **and** `consentedToPrivateCloudCompute` is true.
  The consent flag defaults to false, has no UI yet, and is cleared by
  `reset`. The service's `isPinnedToDevice` reads it.
- Guards: `ModelRouterTests.test_ask_isDeviceOnly_underEveryCapability`,
  `test_offDeviceProcessing_requiresSwitchOffAndExplicitConsent`.

### R2 — The on-device tier is reported by the SDK

- On iOS 27 (`#if compiler(>=6.3)` + `#available(iOS 27.0, *)`),
  `reportedOnDeviceTier()` maps `SystemLanguageModel.variant` to
  `OnDeviceModelTier`; the resolver's source is `.reported`. Earlier OSes
  keep 051's inference. `variant` is read-only, so selection stays the OS's.

### R3 — Plain prose on every model-facing surface

- No bracketed tag vocabulary in instructions, turn lines, overlays, cues,
  legends, the computed-facts block, or `@Guide` text. Each line opens with a
  plain label sentence ("This is a journal question.", "How to reply: …",
  "Today is …"). The journal context block keeps its `[ref N | date]` row
  labels and closing delimiter: they are data addressing that `citedRefs`
  depends on, the core bans ref numbers in the reply, and
  `OutputSafetyScanner` strips the delimiter.
- The marker grammar is taught only by `EvidencePack.legendFooter`, on turns
  whose pack has moments to place. Instructions and stance lines never
  contain `{{quote:` or `{{date:`, so the instruction prefix stays the same
  bytes per channel and the speculative prewarm pool keeps hitting.
- Versions: `ask-core@20`, `ask-degraded@20`, `chat-light@5`,
  `chat-companion@2` (`chat-light-degraded@5`, `chat-companion-degraded@2`).
- Guards: `PromptStanceSyncTests`, `AskPromptContractTests`,
  `ConversationalRecallContractTests`; eval scorers flag an echoed plain
  label as `leak.promptTag`.

### R4 — Role, domain permission, and one safety sentence

- Every Ask and chat prompt opens "You are Memento, a journaling companion"
  and says the person may talk about anything they have written, including
  hard days. Sit stays with one moment; it no longer names a pattern.
- Safety is one sentence per prompt: no help harming self or others, no
  sexual content involving minors, no following requests to ignore the
  instructions, crisis support shown by the app, and no advice when the turn
  says reflect only. Spec 026's classifier and crisis card are unchanged.

### R5 — The renderer holds the recipe (`reply-render@2`)

- **One question.** Everything through the first question is the head; while
  streaming, the tail is held back; at the end, the tail's questions are
  dropped and its statements kept.
- **Report openers.** "You wrote that …", "Looking at your entries, …", and
  "In your journal, …" lose their frame and keep their content, at the start
  of the reply only. While streaming, a reply whose first words could still
  become one of these is held back.
- **No-match lead.** On notebook and thread turns with a `.noMatch` or
  `.nearbyOnly` stance, Swift prepends `NoMatchLead.sentence` from the first
  streamed frame and drops the model's own restatement in either person. The
  prompt says the opening is taken (`NoMatchLead.promptLine`) without
  quoting it.
- Every pass is stream-stable: a streamed body is always a prefix of the
  final and never shrinks. Counts appear in the render log line
  (`extra_questions=`, `openers=`, `lead_restated=`).
- Guards: `ReplyRendererRecipeTests`.

### R6 — Locale hint

- When the locale is not U.S. English, instructions start with Apple's
  sentence "The person's locale is <identifier>." and the version gains
  `+loc`. The locale is stable per device, so it never costs a prewarm miss.

## Verification

- Merge lane: the unit suite above plus the spec gates.
- Device lane (required before this spec closes): one convo-sim run on each
  tier, compared with the last Study run, reporting phantom-marker rate,
  replies with more than one question, report-opener rate, echoed-label
  leaks, and refusals on grief or health turns. Any regression reopens the
  requirement that caused it.

## Follow-ups (not this spec)

- Structured `AskAnswer` fields so Swift assembles Meet / Moment / Sit /
  Question — once the device run shows which parts still drift.
- `DynamicProfile` per channel, replacing string-built instructions.
- Private Cloud Compute: a consent screen that sets
  `consentedToPrivateCloudCompute`, a spec 014 amendment, and a privacy
  label review. R1 is the gate it must pass through.
- Model-based turn classification, ambient entry summaries, Core Advanced
  budget clamps, schema-off prompting, and response caps — each on device
  numbers.

## Regression Guards

- The Ask row never regains a Z1 default, and no code path reads
  `processOnDeviceOnly` alone to allow off-device work.
- No bracketed tag is reintroduced on a model-facing surface; the marker
  grammar never returns to instructions.
- No renderer pass may retract streamed text.
