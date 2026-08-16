---
id: 028
title: Ask Output — Bounded Markdown and Generative UI
tier: P2
status: not-started — plan authored 2026-08-16; do not implement until gates in §Gates
effort: 4 sessions once unblocked (M1–M4); M5–M6 separately after Patterns + iOS 27 tools
depends_on: [017, 018, 019, 026]
findings: [ask-output-dialect-split, markdown-prompt-renderer-drift, genui-parts-envelope, computed-not-generated]
source_refs: [REQ-INT-012, REQ-INT-014, REQ-SUR-001, REQ-SUR-002, REQ-SUR-003, REQ-SUR-004, REQ-VOX-006, P3, P6]
tech_refs: [technology/01-foundation-models.md, technology/03-spotlight-retrieval.md, technology/06-speech-and-audio.md, technology/09-ui-swift6-testing.md]
pres_refs: [PRES-042, PRES-043, PRES-044, PRES-047]
---

# 028 — Ask Output: Bounded Markdown and Generative UI

**This spec is a plan.** It records the long-term shape of Ask replies so
Markdown and GenUI land as one dialect, not two competing rewrites. No Swift
changes belong to this spec until the gates in §Gates are green.

**Ideation (not contract):** lo-fi use cases and wireframes live in
[`reference/028-ask-genui-ideation.md`](reference/028-ask-genui-ideation.md) —
more lookups, the eight primitives, and the restraint filter. That file is
exploratory; this spec remains the dialect source of truth.

**Implementation map (not Swift):** send conditions, thresholds, AFM call
kinds, and success metrics live in
[`reference/028-ask-genui-implementation-map.md`](reference/028-ask-genui-implementation-map.md).
Swift selects the asset; AFM writes the caption — or is skipped.

**Traceability:** extends spec [019](019-surfaces.md) R5 (Ask restores
PRES-040…048; computed answers, not just prose) and the snapshot-streaming
contract in spec [017](017-intelligence-boundary-and-prompt-architecture.md)
R5/R6. Voice split is already in spec [018](018-capture-and-voice-output.md)
R7: chat is markdown-bearing and sanitized at TTS; reflections stay
speakable-by-construction. Safety stays spec [026](026-behavioral-safety-guardrails.md)
— crisis and hard-refuse are never GenUI parts.

---

## Why

Ask today has one layout: optional `heading1` / `heading2` plus a prose `body`,
with citations as chrome around it. That is enough for a conversation. It is
not enough for the questions the empty-state prompt pool already asks
("how many times…", "what are the recurring themes…"), which spec 019 R5
already specified as **computed sections** (`.count` / `.statistic` / `.table`
/ `.scoredItems`) rather than a prose guess.

Two richness tracks are in scope, together:

1. **Bounded Markdown** in the prose channel, so emphasis and short lists can
   render instead of being banned by `ask@6` while `RichTextParser` already
   knows how to draw them.
2. **GenUI** as a closed catalog of `@Generable` parts the model may choose
   and order, mapped onto views we already own — never as the model writing
   SwiftUI.

They compose in one turn. Markdown is not a way to fake a chart. GenUI is not
a way to replace the chat bubble with a generated screen.

---

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | Prompt and renderer disagree on Markdown. `ask@6` forbids bold, italics, bullets, and headings in the body. `RichTextParser` already styles `**bold**`, `*italic*`, and `- ` lists. `SpeechTextSanitizer` exists specifically because "chat bodies legitimately contain markdown." | `PromptRegistry.swift` (`ask@6` "Output: plain spoken prose only"), `RichTextParser.swift`, `SpeechTextSanitizer.swift` header, spec 018 R7 | MEDIUM — product is already two-minded |
| 2 | PRES-042 promises "markdown-safe parsing" on a heading/body typewriter. There is no part list, so every Ask turn is forced through `AIOutputComponent`. | `frontend-preservation-contract.md` PRES-042; `AIChatView.swift` → `ChatMessageBubble` → `AIOutputComponent` | MEDIUM — the host is right; the schema is too small |
| 3 | Spec 019 R5 already requires computed answers ("how many times did I write about my brother this year?" → a `.count` section, not a prose estimate) and `queryToken`-keyed sections. Nothing in `AskAnswer` can represent those. | spec 019 R5; `AskAnswer` in `FoundationModelsIntelligenceService.swift` (`heading1`, `heading2`, `body`, `citedRefs`) | HIGH against the 2.0 Ask contract; not a 1.0 ship blocker |
| 4 | Persistence is a JSON string `{heading1, heading2, body, sources}` scraped on reload. A richer reply will rot or leak raw JSON into the bubble (the failure `AIOutputContent.sanitizeBody` already exists to hide). | `LocalChatStore.StoredMessage.content`; `ChatViewModel.extractBodyContent` | HIGH once parts exist; LOW today |
| 5 | Retrieval is deterministic `EntryRetriever`, not `SpotlightSearchTool`. `GenerationRequest.toolsEnabled` is `false`. Pipeline payloads (`.count` / `.table` / …) are iOS 27 work owned by spec 016. | `FoundationModelsIntelligenceService.prepareAsk`; spec 016 R5 | Constraint, not a defect — GenUI v1 must bind Swift-side aggregates, not wait on the tool loop |
| 6 | Safety and citations are already proto-GenUI: `ChatMessageBubble` switches on `safetyPresentation`; citations are reconciled against retrieval and rendered as `CitationLink`, not as `[ref N]` in the body. | `ChatMessageBubble.swift`; spec 026; `AskAnswer.citedRefs` | Strength — extend this switch, do not replace it |
| 7 | Chart components exist and are parked for Patterns (`SentimentAnalysisCard`, `PercentageBarChart`, `KeywordsCard`). Putting them in chat before Patterns owns sample-size disclosure (`REQ-SUR-001`) will invent trends. | spec 019 R4; preservation contract §4 reuse ledger | Do not pull into M1–M4 |

---

## The dialect

An Ask turn is an **ordered list of parts**. Two families share that list.
The model may choose and order parts from a closed catalog. The renderer is
deterministic SwiftUI. The model never emits views, HTML, or a component graph
of stacks/spacers/colors.

```
AskReply
  parts: [AskPart]          // order is layout order
  citedRefs: [Int]          // still reconciled in Swift; never in markdown
```

```
AskPart
  ├── markdown        → RichTextParser (bounded subset)
  ├── reviewedJournals→ CitationLink / JournalReviewIndicator
  ├── nothingFound    → REQ-SUR-003 empty + "what I searched"
  ├── count           → labeled number + n (value from Swift, not the model)
  ├── statistic       → labeled value + n
  ├── entryList       → CitationTimelineList
  ├── table           → later; pipeline `.table` or Swift aggregation
  ├── lowConfidence   → REQ-SUR-001 greyed / "too few to call a pattern"
  └── chart           → M5 only, after Patterns owns the same component
```

Crisis resource and hard-refuse stay **outside** this catalog. Spec 026 routes
them before generation. A part named `crisisCard` or `adviceChips` is a
spec defect if anyone adds it.

### Channel 1 — Bounded Markdown

Markdown is the **prose** channel. It is how a conversational reply gets
emphasis and a short list. It is not how Ask draws data.

**Allowlist (Ask `markdown` parts only):**

| Syntax | Render | Speak |
|---|---|---|
| `**bold**` | `RichTextParser` bold font | sanitizer keeps inner text |
| `*italic*` | italic | sanitizer keeps inner text |
| `- ` unordered list | bullet glyph | sanitizer drops the marker, keeps the item |
| (optional, same session as lists) `1. ` ordered list | number | sanitizer drops the marker |

**Denylist (always):**

- ATX headings (`#`…`######`) in the body — titles stay `heading1` / `heading2` fields so typography tokens and typewriter order stay stable (`DEC-028-1`, resolved below)
- Images, HTML, raw `<tags>`
- Markdown tables — a table is a GenUI `table` part, or it does not ship
- Markdown links and bare URLs — citations are GenUI; links are a review and speakability hazard
- Emoji
- Reference markers (`[ref 2]`, `[2]`) — still stripped; still belong only in `citedRefs`
- Fenced code / inline code — no journaling use

`heading1` / `heading2` remain structured optional fields on the reply (or on
the leading `markdown` part), not `#` lines. They already stream in
declaration order and map to `type.h3` / `type.h4`. Folding them into
Markdown headings would fight PRES-042 and the typewriter.

**Prompt vs reflection:** `ask@N` (N > 6) **allows** the allowlist in `markdown`
parts and **forbids** everything else. Reflection prompts stay on
`SpeakabilityLinter` / `REQ-VOX-006` with no Markdown at all. CONSTITUTION §4
rule 4 already scopes the linter to reflection body/observation; this spec
does not relax that. Chat continues to use `SpeechTextSanitizer` (018 R7).

### Channel 2 — GenUI

GenUI is the **data** channel. The model selects **which** computed artifact
to show. Swift (today: `EntryRetriever` + local aggregation; later: spec 016
`CustomStage` / `SearchPipelineData`) supplies the numbers, rows, and n.

House rule, copied from spec 019 R4 and non-negotiable here: **charts and
counts are computed, not generated.** If the model emits `value: 42` and
retrieval counted `11`, the renderer shows `11`. The model's numeric fields
on computed parts are either ignored or used only as a requested label, never
as the displayed quantity.

First catalog (M2–M4), mapped onto views that already exist:

| Part | Who computes | Renderer | Speakable form |
|---|---|---|---|
| `markdown` | Model | `AIOutputComponent` body path | `SpeechTextSanitizer` |
| `reviewedJournals` | Retrieval (already known before first token) | `CitationLink` / `JournalReviewIndicator` | "Reviewed N journals." |
| `nothingFound` | Empty retrieval + `REQ-SUR-003` | Designed empty copy + search window | The copy itself |
| `count` | Swift aggregate / later `.count` | Labeled number + n | "N times, based on M entries." |
| `entryList` | Retrieval / later `.scoredItems` | `CitationTimelineList` | Dates + titles, or skip if caption empty |
| `lowConfidence` | Threshold on n (`REQ-SUR-001`) | Greyed / annotated, or omit the chart | The annotation copy |

Later catalog (M5–M6), not in the first `@Generable` type:

| Part | Gate |
|---|---|
| `statistic` / `table` | Spec 016 pipeline stages live, or a Swift aggregate with the same n rule |
| `chart` | Spec 019 R4 Patterns owns the component and sample-size disclosure; then chat may inline the **same** view, never a parallel chart |

### Coexistence rules

These are the load-bearing product rules. Implementation that violates one
is out of contract even if it "works."

1. **One turn, one list.** Markdown and GenUI parts interleave in `parts`.
   Typical grounded analytical reply: `reviewedJournals` → `markdown` → `count`
   or `entryList`. Typical casual reply: a single `markdown` part. Typical miss:
   `nothingFound` only (prose is inside that part's copy, not a second guess).
2. **Do not double-encode.** If a `count` part is present, the markdown part
   must not also guess the number. If an `entryList` is present, markdown must
   not inventory the same entries as a bullet list. The prompt says this; eval
   (spec 022) should eventually catch it.
3. **Data never travels as Markdown.** No markdown tables, no "1. date — excerpt"
   lists as a substitute for `entryList`, no ASCII bar charts.
4. **Citations never travel as Markdown links.** `citedRefs` + `reviewedJournals`
   / `entryList` remain the only citation surfaces. PRES-044 (sheet, then
   tap-through) is unchanged.
5. **Safety never travels as a part.** Spec 026's card and authored refusal
   stay a `ChatMessageBubble` presentation switch, same as today.
6. **The model does not mint actions.** "Save as entry", regenerate, speak,
   thumbs, and suggestion chips stay chrome (`PRES-043` / `PRES-046` /
   composer). `FollowUpQuestionGroup` is a Patterns/weekly candidate, not an
   Ask GenUI part — it invites the advice the archivist (`REQ-SUR-002`) must
   refuse.
7. **Speakable by construction still holds (P6), as a dual path.** Every
   `markdown` part is sanitizable. Every GenUI part either has a short
   speakable caption or is skipped by `VoicePlaybackService`. A chart with no
   caption is not spoken as "image" or as axis ticks. Playback remains
   post-stream only (018 R7).
8. **P3 is unchanged.** Only `FoundationModelsIntelligenceService` imports
   `FoundationModels`. `AskResult.parts` on `IntelligenceService` is a
   protocol type. `ChatViewModel` / `AIChatView` never see `@Generable`.

---

## Resolved decisions

Recorded here so an implementer does not re-litigate them. Reopen only with
an explicit amendment to this spec.

| ID | Decision | Why |
|---|---|---|
| `DEC-028-1` | Keep `heading1` / `heading2` as structured fields. Markdown headings in the body are denylisted. | Typewriter order, typography tokens, and PRES-042 all assume two heading slots. `#` in a streamed body fights that for no gain. |
| `DEC-028-2` | Allow `- ` (and, if cheap, ordered) lists in Ask markdown parts. Reflections still forbid them. | Lists are the main reason to have Markdown at all in a journal companion. `SpeechTextSanitizer` already strips markers. |
| `DEC-028-3` | Charts-in-chat are M5, after Patterns. M1–M4 may not mount `SentimentAnalysisCard` / `PercentageBarChart` in a bubble. | `REQ-SUR-001` (show n; suppress below threshold) lives on Patterns. Inlining first would duplicate the chart subsystem and skip the disclosure rule. |
| `DEC-028-4` | GenUI v1 binds Swift-side aggregates from the current `EntryRetriever` result. It does not wait for `SpotlightSearchTool`. | The iOS 26 SDK path has `toolsEnabled: false`. Waiting on 016's tool loop parks the whole dialect. M6 replaces the binding with pipeline payloads when that loop ships. |
| `DEC-028-5` | Persistence is a versioned envelope (`ask-parts@1`), not a richer scrape of a single JSON string. Unknown `kind` values decode as skippable so an older app can open a newer transcript as markdown-only. | `extractBodyContent` is already the leak path for raw JSON. Parts will make it worse unless the store is versioned first (M2). |

---

## Milestones

Do not start a later milestone while an earlier one's exit is red. M0 is this
document.

### M0 — Plan (this spec)

Author the dialect, coexistence rules, and gates. No Swift.

**Exit:** this file on `main` (or `dev` once that branch exists); ROADMAP row
present; 019 R5 points here.

### M1 — Align Markdown (one session, unblocks the dialect)

Make the three Markdown minds agree, still on the current heading/body layout.

- Bump Ask prompts to `ask@7` / `ask-degraded@7`: allow the allowlist in the
  body; keep the denylist; keep "no `[ref]` in the body."
- Document the allowlist next to `RichTextParser` (the parser is the
  renderer contract; the prompt must not promise syntax the parser drops).
- Add parser tests for the allowlist and denylist (denylist renders as
  literal text or is stripped — pick one and test it; do not silently
  interpret `#` as a heading).
- Confirm `SpeechTextSanitizer` covers every allowlist construct (it already
  does for bold/italic/lists/links/headings).
- Do **not** change `SpeakabilityLinter` or reflection prompts.
- Do **not** introduce parts yet.

**Exit:** a casual Ask turn can legally contain `**bold**` and a short list;
TTS reads the inner text; reflections still fail the linter on the same
markers; prompt version tests pin `ask@7`.

### M2 — Parts envelope (one session, persistence-first)

Introduce `AskPart` on the intelligence protocol and a versioned store
envelope **before** adding new visual kinds.

- `AskResult` / `AskStreamEvent` carry `parts` (at least one `markdown` part
  equivalent to today's body).
- `LocalChatStore` writes `schema: "ask-parts@1"`. Reload of old
  `{heading1,heading2,body,sources}` sessions still works.
- `ChatMessageBubble` can render a list of parts, with today's
  `AIOutputComponent` as the `markdown` renderer.
- Unknown kinds skipped. Reloaded history does not replay the typewriter
  (`isNew == false` already exists).
- Streaming: properties still fill in declaration order. Put `markdown`
  first in the `@Generable` struct so the typewriter starts immediately.
  Computed parts insert with the same move+opacity transition already used
  for citations (do not shove the body mid-read).
- Action bar stays gated on `!isStreaming` (PRES-043).

**Exit:** a round-trip test: send → persist → kill → reload yields the same
visible parts; an old session still opens; a fixture with an unknown `kind`
shows the markdown part and nothing else.

### M3 — Honest empty + reviewed-journals as parts (one session)

Lift chrome that already exists into the catalog, so GenUI is not "the first
new widget" — it is the existing Ask contract made explicit.

- `reviewedJournals` is a part, fed from the first-delta `reviewedCitations`
  path that already exists.
- `nothingFound` is a part, with copy that names the search window
  (`REQ-SUR-003`). Prompt stance `[Turn: journal question, no matches]`
  emits this instead of a markdown apology that invents a pattern.
- Restore PRES-040 suggestion cards only for queries this catalog can
  actually answer (count / last-wrote-about / themes). Corpus questions
  against an empty journal stay suppressed (`AIChatView.hasEntries`).

**Exit:** 019 R5's `doneGrounded-empty` state is a part, not an alert; the
"Reviewed N journals" link is still the first visible chrome on a grounded
turn; suggestion-card audit (019 R6) still finds no advice framing.

### M4 — Computed `count` and `entryList` (one to two sessions)

The first GenUI that changes what a reply *is*.

- Swift aggregates over the current retrieval set (count of matching
  entries; dated list). Bind those values into the prompt as facts the
  model may **surface**, not invent (`DEC-028-4`).
- `@Generable` parts for `count` and `entryList` carry labels and ids, not
  the displayed number/rows as model-authored fields — or the renderer
  overwrites them from the bound payload.
- `entryList` rows tap through to the cited entry (the sanctioned PRES-044
  upgrade in 019 R3/R5).
- Coexistence rule 2 is tested: a fixture question "how many times did I
  write about X" yields a `count` part whose value matches the retriever,
  and the markdown part does not contain a conflicting numeral.
- Voice: `count` has a caption; `entryList` is skipped or summarized
  ("Three entries, from March to July.").
- Degraded Z0 path: prefer `markdown` + `nothingFound` / `lowConfidence`
  over a dense `entryList` the smaller model will mishandle. Never silently
  show a worse chart-like list.

**Exit:** the 019 R5 acceptance "how many times did I write about my brother
this year?" renders a computed `count` with its label and n, not a prose
estimate; thumbs/copy/regenerate still attach to the **turn**, not the
count subtree.

### M5 — Charts in chat (after Patterns)

Only after spec 019 R4's Patterns tab claims the chart-subsystem reuse
ledger and `REQ-SUR-001` (n on every correlation; low-n state) is real.

- Chat may inline the **same** chart view Patterns uses, as a `chart` part,
  for questions that are already answered by a computed stage (mood valence
  over a window, cadence).
- Low-n → `lowConfidence` or omit. Narration still reads the chart, never
  the reverse.
- Do not build a second chart design system inside `Components/AIChat/`.

**Exit:** a chat chart and a Patterns chart for the same window show the
same n and the same low-confidence treatment.

### M6 — Pipeline payloads (iOS 27 tool loop)

When spec 016's `SpotlightSearchTool` + `CustomStage` path is wired and
`ToolCallingMode.required` is the Ask setting:

- Replace prompt-side bound aggregates with `SearchPipelineData` payloads
  keyed by `queryToken` (019 R5: unmerged tokens render as two sections,
  never one blended list).
- `MoodValenceStage` / `CadenceStage` / `RecurrenceStage` / `SalienceStage`
  as specified in `technology/03` §9.
- Schema complexity is a context-budget cost (`technology/01` `@Generable`
  warning). Keep the catalog tiny; do not add `@Guide` on fields whose
  names already describe them.

**Exit:** 016's consumption test (two `queryToken`s → two UI sections)
passes at this UI layer, which is the 019 R5 acceptance already written.

---

## Gates (do not implement before)

| Gate | Why it blocks |
|---|---|
| Spec 019 Ask restore of PRES-040…048 is in progress or done — the host (`AIChatView` / bubble / action bar / citations / history) is the thing being extended | GenUI that replaces the bubble fights the preservation contract |
| Spec 026 safety routes remain pre-generation and non-generable | A part catalog that can emit counseling is a P0 |
| Spec 018 R7 chat TTS + `SpeechTextSanitizer` remain the Ask speak path; `SpeakabilityLinter` remains reflection-only | Mixing the two validators will either ban Markdown in chat or allow Markdown in weekly audio |
| Spec 017 P3 (single FoundationModels importer) and `@Generable` contracts | Parts generated in a view model would break the boundary |
| M5 additionally: spec 019 R4 Patterns + `REQ-SUR-001` | Charts without n |
| M6 additionally: spec 016 R5/R8 (tool wiring + recall@5 gate) | Computed parts on a retriever that does not recall are confident lies |

This spec does **not** block Gate S (App Store submit). It is P2 richness on
top of a shipping Ask surface.

---

## Constitution and contract amendments (when M1/M2 start, not now)

Do not edit these files in the planning PR. When implementation starts:

- **PRES-042** — extend, do not replace: "AI responses are an ordered part
  list; `markdown` parts use the bounded subset and the existing typewriter;
  computed parts are first-class sections. JSON never shown raw."
- **CONSTITUTION §4 rule 4** — already scopes speakability lint to
  reflection. Add one sentence: Ask `markdown` parts are allowlisted and
  sanitized at TTS; they are not linter-gated.
- **`REQ-VOX-006` reading in the architecture spec** ("every prompt producing
  user-facing prose MUST forbid markdown") — amend to "every **reflection**
  prompt…"; Ask is the documented exception with an allowlist + sanitizer.
  House rule 1 in `technology/01` §12 the same way.
- **Prompt version** — `ask@7` (M1), then a parts-aware version when M2
  changes the `@Generable` shape. Do not silently mutate `ask@6`.

---

## Limitations (standing)

These are reasons to keep the catalog small, not puzzles to solve in M1.

- **On-device model + context.** Nested optional unions are skipped or
  duplicated. Every extra schema token competes with journal evidence.
  `ContextBudget` already cannot read `contextSize` on the iOS 26 SDK.
- **Z0 vs Z1.** Dense part lists will look worse on-device, not "the same UI,
  shorter." Degrade to markdown + `nothingFound` / `lowConfidence`.
- **Streaming layout.** Snapshot parts that insert above streamed text shove
  the reader. Declaration order and reserved height matter more than
  animation polish.
- **History.** Old sessions have no parts. Reload must degrade. Feedback is
  per-turn, not per-part, in M1–M4.
- **Persona.** Any part that advises, diagnoses, comforts, or asks a stack of
  follow-ups is out. Eval (`PersonaGate`) applies to markdown **and** to
  visible labels on computed parts.
- **Not a generated screen.** Composer, history sheet, empty state, and
  action bar stay the preserved Ask chrome. GenUI lives *inside* a bubble.

---

## Out of Scope

- Implementing any milestone in the same change as this plan.
- Letting the model emit SwiftUI, HTML, or unconstrained Markdown.
- A generic component graph (VStack, colors, buttons as model output).
- Third-party LLM providers (Z2) as a way to get "better GenUI."
- Changing weekly/monthly/entry reflection output to Markdown (`REQ-VOX-006`
  stays).
- Crisis counseling widgets, advice chips, mood-wheel-before-you-write.
- Patterns tab itself (019 R4) — this spec only consumes its charts in M5.
- `SpotlightSearchTool` wiring (016) — this spec only consumes it in M6.
- Fixing the chat-summary `onSave` gap in `AIChatView` (noted there; not this
  dialect).

---

## Tasks

**Do not check these in the planning PR.** They are the implementation order
once §Gates are green.

- [ ] 0. Keep this spec as the dialect source of truth; bump status to
      `in-progress` only when M1 starts.
- [ ] 1. M1 — `ask@7` allowlist, parser tests, no parts, no linter change.
- [ ] 2. M2 — versioned `ask-parts@1` envelope, protocol `parts`, bubble
      list, unknown-kind skip, old-session reload.
- [ ] 3. M3 — `reviewedJournals` + `nothingFound` as parts; suggestion-card
      restore only for catalog-answerable prompts.
- [ ] 4. M4 — Swift-bound `count` + `entryList`; coexistence tests; speakable
      captions; Z0 degradation rule.
- [ ] 5. Amend PRES-042 / CONSTITUTION / `REQ-VOX-006` wording as listed in
      §Constitution — in the M1 or M2 PR, not before.
- [ ] 6. M5 — charts-in-chat after Patterns (separate spec harvest if this
      file is too large by then).
- [ ] 7. M6 — pipeline payloads after 016's tool loop (same harvest rule).

## Verification

Planning-only (this PR):

- [ ] ROADMAP lists spec 028 as plan-authored, implementation gated.
- [ ] Spec 019 R5 points here as the follow-on for computed answers +
      Markdown.
- [ ] No `MeetMemento/` Swift changes in the planning change.

When a milestone ships, that PR adds Given/When/Then under the milestone's
**Exit** and runs the online suite (`CI_ONLINE=1` … `-skip-testing:MeetMementoUITests test`).
Live FM generation stays on `ios-device-eval.yml`.

## Regression Guards

- PRES-040…048 Ask chrome (empty state, three-state input, typewriter,
  action bar, citations, history, summarize, retry, gating) — extend 042/044,
  do not replace the bubble.
- P3 / REQ-INT-001 — one FoundationModels importer.
- P6 / REQ-VOX-006 — reflections remain linter-clean; Ask sanitizes.
- REQ-SUR-002 archivist persona — no advice parts.
- REQ-SUR-003 grounded or silent — `nothingFound` is a part, not world knowledge.
- REQ-SUR-004 / spec 026 — crisis card stays static and pre-generation.
- REQ-INT-012 — structured output stays `@Generable`, no JSON-in-a-string
  parsing. M2's envelope is a store format, not a generation format.
- CONSTITUTION logging / no-Z2 / typography tokens on any new part labels.
