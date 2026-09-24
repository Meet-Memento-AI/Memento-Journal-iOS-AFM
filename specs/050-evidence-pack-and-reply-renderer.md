---
id: 050
title: Evidence Pack and Reply Renderer — The Model Points, Swift Quotes
tier: P1
status: done (2026-09-23 — re-sim complete; see Study III and spec 051 for the residuals)
effort: 1 session, landed as stacked commits (see Tasks)
depends_on: [017, 037, 039, 044, 046, 049]
findings:
  - italic-quote-contract-asks-the-model-to-witness
  - thread-grounding-has-no-quote-verification
  - ambient-rows-quotable-like-citations
  - invented-dates-in-glue-prose
  - quoted-field-and-legend-drift
  - main-does-not-compile-shape-redeclaration
  - ask-core-over-the-size-gate
source_refs: [REQ-REF-001, REQ-REF-002, REQ-REF-003, REQ-REF-004, REQ-REF-005, REQ-REF-006, REQ-REF-007, REQ-EVD-005, REQ-INT-001, REQ-PRM-004]
tech_refs: [technology/01-foundation-models.md, technology/04-evaluations.md]
---

# 050 — Evidence Pack and Reply Renderer

**Traceability:** the post-retrieve half of spec
[`046`](046-grounding-and-evidence-discipline.md) R5 ("evidence-typed claims"),
taken one step further than 046 asked. Spec
[`037`](037-conversational-recall-experience.md) set the rule *code decides,
the model renders*; this spec narrows it to **code owns the reference, the
model owns the glue.** Channels stay [`039`](039-reply-channels-and-phatic-generation.md),
retrieval stays [`044`](044-agentic-harness-depth.md), the evidence ladder and
response policy stay [`049`](049-epistemic-voice-and-response-policy.md)
(R3's `exact` copy is amended here). Privacy stays
[`014`](014-privacy-model-and-trust-boundary.md): everything in this spec is
Z0. This spec mints the **`REQ-REF-`** series inline.

**Does not implement:** two-stage candidate generation, ANN, multi-query
retrieval, date/entity prefilters, RetrievalGate warehousing (all 044 / P1
retrieval), a larger `maxEntries`, a new passage chunker, cloud reranking, or
any change to what leaves the device.

## Why

Study II (2026-09-21, persona arm, 262 entries over nine months) routed most
follow-ups to `thread` and produced **56.6% invented material**, dominated by
`hall.fabricatedQuote` ×911 — while 40.5% of turns carried citations, so the
fabrications *looked* grounded. The empty arm improved on the same pipeline
(gating 18.0% → 5.5%), so this is not an empty-recall regression; it is the
grounded path lying in a trustworthy format.

The root cause is a contract, not a model size. After retrieval, the stance
line and `ask-core` still ask a ~3B on-device model to write an **"italic
exact quote"**. The model cannot verify a substring against the journal, and
under TrustZone Z0 the journal never leaves the device, so a bigger model is
not an option. The model is being asked to be a *witness*; it can only be a
*composer*.

The fix makes unverifiable references **inexpressible**: the model never
writes journal quotes or journal dates as free text. It places typed markers
— `{{quote:n}}`, `{{date:n}}` — that point at an `EvidencePack` Swift built
from retrieval, and a `ReplyRenderer` expands them, strips anything
quote-shaped the pack cannot back, and hands the UI chips that come from the
pack, never from the model's italics. The statistic channel already works
this way (`InsightEngine`, `modelIdentifier: "swift"`); quotes and dates now
follow the same template.

## Outcome (re-sim, 2026-09-23)

The re-sim this spec listed as pending is Study III:
`eval-archive/convo-sim/full-2026-09-23-resim.jsonl`, 6,858 messages, 200
conversations, pre-registered at `1689c22` before it ran. Write-up:
[`docs/CONVERSATION_SIMULATION_STUDY_III.md`](../docs/CONVERSATION_SIMULATION_STUDY_III.md).

**The spec did what it was built to do.** On the 262-entry nine-month journal,
invented material fell **56.6% → 2.0%** and `hall.fabricatedQuote` **911 → 0**, with
seeded median latency unchanged (4.50s → 4.57s) and the citation rate holding
(40.5% → 38.6%). Against R7's acceptance table: empty-arm gating landed at 6.4%
against a "must not regress above ~6%" bar — a small miss, attributable to finding 2
below; the persona fabrication drop is the "sharp drop" R7 asked for.

**Two registered predictions failed, and both fall on the report that made them, not
on this spec.** The 2026-09-22 report predicted the model would keep emitting
unverifiable references for the renderer to remove, on ≥25% of seeded turns. The
renderer intervened on **2.4%**. The limit was the contract, not the parameter count:
told to point rather than to italicise, the model largely stopped reaching for the old
vehicle. That report's §5 overstates the case and is superseded by
[`051`](051-reference-discipline-and-temporal-retrieval.md)'s Why.

**Three residuals, all owned by 051.** The model does not reliably *point* — 100 of
641 matched turns expanded a quote marker, and it paraphrases instead, trading
fabrication for vagueness that nothing measures. Markers were emitted against an empty
pack on 184 turns, because `ask-core@19` teaches the grammar unconditionally and
`noneNote` then forbids it. And prompt scaffolding reached user-visible text 34 times,
against zero in the two prior studies — the only outright regression.

## Current State (evidence)

> Verified 2026-09-22 against `main` @ `5fa700f` ("Land the evidence-first Ask
> harness", PR #32). Line numbers rot — re-verify before editing.

| # | Finding | Evidence | Severity |
|---|---------|----------|----------|
| 1 | **The grounded stance asks the model to author the quote.** `TurnStance.journalGrounded.promptLine` says "one ### notebook moment, italic exact quote … reproduce any quoted field exactly". | `Retrieval/RetrievalPolicy.swift:70-77` | **Critical** |
| 2 | **`ask-core@18` grants italics as the journal-quote vehicle** in four places: the Notebook bullet ("short exact quote in *italics*"), the markdown grammar ("italics for exact journal quotes only"), "a journal line is an italic quote", and both notebook suffixes ("italic quote"). The degraded core repeats it ("italic quotes"). | `Prompt/PromptRegistry.swift:419-421, 431-435, 437-439, 562-581, 486` | **Critical** |
| 3 | **The `@Guide` twin repeats it.** `AskAnswer.body` ends its markdown subset with "italics for an exact journal quote"; `AskAnswerGuides.body` is the testable copy. | `FoundationModelsIntelligenceService.swift:85, 95` | High |
| 4 | **The ladder writes journal text and a raw date into the prompt.** `EvidenceLadder.promptLine(.exact)` emits "You wrote *<80 chars>* on *MMM d, yyyy*." — a banned opener, pasted journal text, and a date in a different format from the context block's "MMMM d, yyyy". | `Evidence/EvidenceLadder.swift:53-59, 79-84` | High |
| 5 | **Nothing verifies a quote before it reaches the screen.** `makeResult` strips reference markers and runs `reconcileCitations`, whose `quotedRefs` only *adds* citations for verbatim 30-char windows. A fabricated italic span passes through untouched, on every channel. | `FoundationModelsIntelligenceService.swift:1232-1280`, `Reconciliation/CitationReconciliation.swift:165-212` | **Critical** |
| 6 | **Thread is the hotspot and has no quote discipline at all.** `threadSuffix` says nothing about quotes; thread + journal anchor ships the evidence block (`followupThread` is never a "miss"), including on **ambient** retrieval. Study II: thread invented 69.4%. | `PromptRegistry.swift:583-587`, `FoundationModelsIntelligenceService.swift:2163-2164` | **Critical** |
| 7 | **Ambient rows ship with `quoted:` fields.** `buildContextBlock` writes a `quoted: "…"` line for every entry, ambient or not, so a background row is exactly as quotable as a topical hit. | `Retrieval/EntryRetriever.swift:1034-1059` | High |
| 8 | **Streaming paints raw model text.** `askStream` yields `strippingReferenceMarkers(snapshot)` on every delta; narration feeds those deltas to TTS through `StreamingSentenceChunker`, whose first-chunk fast path speaks before a sentence ends. Anything the final pass removes has already been seen and possibly spoken. | `FoundationModelsIntelligenceService.swift:1758-1803`, `ViewModels/NarrationCoordinator.swift:537-583` | High |
| 9 | **Citation chips do not mirror the reply.** `AskCitation.excerpt` is `previewExcerpt(entry.text, query:)` — a 120-char window around the first query term — not the words the reply showed. | `CitationReconciliation.swift:183-191, 226-245`, `ChatService.swift:343-353` | Medium |
| 10 | **`main` does not compile.** PR #32 added `let shape = QuestionShapeResolver.shape(…)` beside the existing `let shape = resolveTurnShape(…)` in `finishAskPrep` — an invalid redeclaration. CI never ran (self-hosted runners offline; every run since 2026-09-20 is `queued`/`cancelled`). | `FoundationModelsIntelligenceService.swift:1139, 1146`; `gh run list --branch main` | **Critical** |
| 11 | **`main` fails its own size gate.** `ask-core@18` + notebook suffix is 4,526 characters (measured with `swiftc`); `AskPromptSizeTests` allows 4,518 (55% of 8,214). *Resolved by R3: `ask-core@19` + notebook suffix is 4,499.* | `Prompt/PromptRegistry.swift:396-472, 562-572`, `AskPromptSizeTests.swift:9-21` | High |
| 12 | **R1/R3/R4 from the local `harness/device-report-r1-r3-r4` branch are not on `main`.** No `settleAndStop`, no "ambient → journalGrounded". `main` closed the ambient+noMatch contradiction differently (PR #32): ambient + non-inventory → `.noMatch` **and** the evidence block is withheld; ambient + inventory → `.journalGrounded` with the block. This spec preserves *main's* semantics, not the local branch's. | `Retrieval/RetrievalPolicy.swift:212-228`, `FoundationModelsIntelligenceService.swift:2160-2167` | — (constraint) |
| 13 | **Reusable parts already exist.** `RetrievedEntry.quotedSpan` (a contiguous span of the excerpt, via `QuotedSpanExtractor`), the whitespace-normalised passage excerpt (`PassageChunker.excerpt`), `EvidenceState` (`none/ambient/matched`), `CitationReconciliation`'s fold. | `EntryRetriever.swift:25-54`, `QuotedSpanExtractor.swift`, `Evidence/EvidenceState.swift` | — (reuse) |
| 14 | **The project half-finished a rename.** `e4d1621` moved `MeetMemento/` → `withMemento/` and `MeetMemento.xcodeproj` → `withMemento.xcodeproj`, but `project.pbxproj`'s synchronized groups still say `path = MeetMemento` / `MeetMementoTests`, CI still passes `-scheme MeetMemento`, and `ConversationSimulation.swift` alone imports `withMemento` (every other test imports `MeetMemento`). New files here follow the on-disk `withMemento/` layout; the rename itself is not this spec's to finish. | `withMemento.xcodeproj/project.pbxproj:61-80`, `.github/workflows/ios-build-online.yml:59-116`, `withMementoTests/Eval/ConversationSimulation.swift:2` | High (blocks every Mac verification step until reconciled) |

## Architecture

### Today

```
User message
  → SafetyRouter.decide                                  prepareAskCore
  → AskPipeline.plan (TurnClassifier → ReplyChannel)     prepareAskCore
  → .statistic ? InsightEngine, skip AFM                 ask / askStream → statisticResult
  → EntryRetriever.retrieve (wide, ≤20)                  adoptAndRetrieve → retrieveWide
  → sliceRetrieval (≤5) → RetrievalPolicy.stance         finishAskPrep
  → buildAskPrompt (stance + ladder + [Shape:] +         finishAskPrep → buildAskPrompt
      Journal evidence block with `quoted:` lines)
  → AFM ~3B writes prose + *italic quotes* + free dates  respondToAsk / streamAskResponse
  → strippingHarnessMarkup → strippingReferenceMarkers   makeResult / emitDelta
  → reconcileCitations(citedRefs, quotedRefs, top-3)     makeResult
  → AskResult → ChatService → bubble + citation sheet
```

### Target

```
User message
  → SafetyRouter → AskPipeline.plan → ReplyChannel       (unchanged)
  → .statistic ? InsightEngine, skip AFM                 (unchanged)
  → EntryRetriever (existing passage path) → slice → stance   (unchanged)
  → EvidencePackBuilder.build(retrieval, stance, channel, archiveEmpty)   NEW
        .none | .ambient | .matched
  → buildAskPrompt(…, evidencePack:)                     evidence block without `quoted:`
        + [Evidence] legend (matched) / background note (ambient) / none note
  → AFM ~3B: glue + {{quote:n}} {{date:n}} only
  → ReplyRenderer.render(raw, pack, context)             NEW — the single choke point
        expand markers from the pack · adopt verbatim spans · drop the rest
        strip unmarked italics · verify bold · ban dates the pack cannot back
  → citations = expanded slots first, reconcile as backstop (matched only)
  → AskResult(body, citations, chips, renderStats) → ChatService → bubble + sheet
  Streaming: every delta is ReplyRenderer over a stable prefix — raw text never reaches UI or TTS.
```

## Requirements

**Zone tag:** every requirement is Z0. Nothing here changes what leaves the
device; `REQ-PRIV-001` is untouched.

### R1. The EvidencePack is built by Swift from what the prompt carries (`REQ-REF-001`)

New file `withMemento/Services/Intelligence/Evidence/EvidencePack.swift`.
No `FoundationModels` import.

```swift
/// One moment the renderer may insert. The model can only point at it.
struct EvidenceSlot: Sendable, Equatable, Identifiable {
    let index: Int            // n in {{quote:n}} / {{date:n}}; equals the entry's [ref n]
    let entryId: UUID
    let date: Date
    let displayDate: String   // EntryRetriever.formattedDate — the notebook-moment format
    let quoteText: String?    // contiguous span of passageText; nil = date-only slot
    let quoteIsClipped: Bool  // span stops mid-sentence; display appends "…"
    let passageText: String   // the excerpt the model saw ([ref n] text)
    var id: Int { index }
}

struct StatSlot: Sendable, Equatable, Identifiable {   // grammar only in v1
    let id: String; let kind: String; let label: String; let spokenMagnitude: String
}

struct EvidencePack: Sendable, Equatable {
    let state: EvidenceState  // reuses the 046 vocabulary; see R1 rules
    let slots: [EvidenceSlot] // empty unless .matched
    let contextDates: [Date]  // dates of every entry whose text the prompt carries
    let stats: [StatSlot]     // empty in v1 — statistic stays skip-AFM
    let retrievalWasEmpty: Bool
    let retrievalWasAmbient: Bool
}

enum EvidencePackBuilder {
    static func build(retrieval: RetrievalResult, stance: TurnStance,
                      channel: ReplyChannel, archiveEmpty: Bool) -> EvidencePack
}
```

Rules — the pack mirrors **exactly** what `buildAskPrompt` ships, so the
prompt and the renderer can never disagree about what evidence exists:

1. `.none` when the channel does not retrieve, retrieval is empty, or the
   turn is a miss (`.noMatch`, `.nearbyOnly`, or an empty archive — the same
   `miss` test `buildAskPrompt` uses today). No slots, no context dates.
   `.noMatch` can never expose a slot, even if rows are attached.
2. `.ambient` when retrieval is ambient (including the inventory case main
   grounds as `.journalGrounded`). **No slots in v1**; `contextDates` carries
   the shipped rows' dates so a true date the model reads from `[ref n | date]`
   is not stripped.
3. `.matched` otherwise: one slot per retrieved entry, in ref order.
   `quoteText` prefers `quotedSpan`, then `QuotedSpanExtractor.candidates`
   (new, returns every clean sentence; `extract` is unchanged). A candidate is
   accepted only if it is a contiguous substring of the entry excerpt and
   contains no markdown or marker control character (`* _ \` { }` or a line
   break); a span clipped mid-word is trimmed back to a word boundary and
   flagged `quoteIsClipped`. No acceptable span → date-only slot.
4. `EvidenceState` keeps its enum; its doc comment is widened: the turn-level
   gate (`.none` = empty archive) and the pack (`.none` = nothing quotable
   this turn) share the vocabulary, and the pack state is never higher than
   the turn state.

**Acceptance:** empty → `.none`; ambient → `.ambient` with zero slots;
matched → slots whose `quoteText` is a substring of `passageText`; `.noMatch`
with rows → `.none`; a non-substring `quotedSpan` is rejected and the next
candidate used.

### R2. Marker grammar (frozen for v1) and the model-facing legend (`REQ-REF-002`)

| Marker | Meaning | Expansion |
|--------|---------|-----------|
| `{{quote:n}}` | the exact words of slot n | `*quoteText*` (italics applied by Swift) + a chip; only on `.matched` packs; once per slot |
| `{{date:n}}` | the date of slot n | `displayDate` |
| `{{stat:id}}` | a computed magnitude | `stats[id].spokenMagnitude` — no live stats in v1, so always dropped |

Parsing is lenient on spacing, case, and single braces (`{quote:1}`,
`{{ Quote : 1 }}`) because a 3B model will drift; anything that does not
resolve — unknown kind, out-of-range n, a quote on a non-matched pack, a
duplicate quote — is **dropped**, never shown. Leftover `{{…}}` / brace runs
are stripped. Nesting is not a thing: a marker is atomic.

**Selection, not generation.** On `.matched` packs the prompt carries a
legend that lists each slot's exact `quoteText` and `displayDate` beside its
markers, so the model *chooses* a slot rather than recalling words:

```
[Evidence]
Markers only — the app swaps each for the entry's exact words or date. …
1. {{date:1}} = March 3, 2026 · {{quote:1}} = "I finally slept through the night."
2. {{date:2}} = March 9, 2026 · no quote
If none fits, use no markers.
```

The context block keeps its load-bearing `[ref n | date] text` lines (the
`citedRefs` addressing scheme) but loses the `quoted: "…"` lines — the
legend supersedes them, and an ambient row must not advertise a quotable
field. Ambient gets a one-line background note (no markers, no quoting, no
italics). A `.none` pack on notebook/thread gets a one-line "no markers this
turn" note. Light channels (phatic / continuer / companion / meta / redirect)
are unchanged: their prompts never mention markers.

**Acceptance:** a grounded notebook or thread prompt contains `[Evidence]`,
`{{quote:1}}`, and the slot's exact quote; it contains neither "italic exact
quote" nor `quoted: "`. An ambient prompt contains no `{{quote:`. Every
existing `PromptContradictionTests` denial invariant still holds.

### R3. Retire the italic-quote contract (`REQ-REF-003`)

- `TurnStance.journalGrounded`: "one ### notebook moment as {{date:N}} and
  {{quote:N}} from the [Evidence] list … never type a quote or date
  yourself". `followupThread` gains the same marker rule.
- `ask-core@19` / `ask-degraded@19`: the Notebook bullet becomes
  "### {{date:N}} heading, then {{quote:N}}"; the markdown grammar drops
  italics entirely ("Never italics"); "a journal line is a {{quote:N}} marker
  or restated in second person"; one sentence defines the markers. The hard
  bans (You wrote / Looking at your entries / In your journal, never write
  `[ref N]`) stay verbatim.
- `notebookSuffix` / `threadSuffix` (and degraded twins) state the marker
  rule; `threadSuffix` now carries it too. Both stay ≤ 6 lines.
- `AskAnswer.body` `@Guide` + `AskAnswerGuides.body`: "no italics; journal
  quotes and dates only as {{quote:N}} / {{date:N}} from the [Evidence] list".
  `LightAskAnswer` is unchanged (light prompts carry no evidence).
- `EvidenceLadder.promptLine(.exact, …, pack:)` → "One entry answers this:
  {{date:n}} {{quote:n}}." (amends 049 R3's fixed copy; no pack → "One entry
  is about this.").
- The default-off exemplar turn is rewritten in marker form.
- `ask-core@19` + notebook suffix must come back **under** the 4,518-character
  gate (finding 11), so the rewrite trims as well as adds.

**Acceptance:** `PromptStanceSyncTests` green with updated expectations; no
stance line, suffix, core, or guide mentions italics as a quote vehicle;
versions read `ask-core@19` / `ask-degraded@19` (`+p4` unchanged);
`AskPromptSizeTests` green.

### R4. ReplyRenderer is the single choke point for Ask bodies (`REQ-REF-004`)

New file `withMemento/Services/Intelligence/Reconciliation/ReplyRenderer.swift`.
No `FoundationModels` import.

```swift
struct QuoteChip: Sendable, Equatable, Identifiable {
    let slotIndex: Int; let entryId: UUID; let date: Date
    let displayDate: String; let quoteText: String   // exactly what the body shows
    var id: UUID { entryId }
}

struct ReplyRenderStats: Sendable, Equatable {       // content-free; loggable
    var packState: EvidenceState; var slotCount: Int
    var expandedQuoteSlots: [Int]; var expandedDateSlots: [Int]
    var adoptedQuoteCount, droppedMarkerCount, droppedDuplicateQuoteCount: Int
    var strippedItalicCount, droppedQuotationCount, unwrappedBoldCount: Int
    var strippedDateCount, droppedHeadingCount: Int; var usedFallback: Bool
}

struct RenderedReply: Sendable, Equatable {
    let body: String              // no markers, ever
    let chips: [QuoteChip]
    let citations: [UUID]         // entries the body actually references
    let stats: ReplyRenderStats
    var expandedSlotIndexes: [Int] { get }
    var strippedItalicCount: Int { get }
    var droppedUnknownMarkerCount: Int { get }
}

struct RenderContext: Sendable, Equatable {        // what the person said in chat
    init(question: String, history: [ChatTurn])
}

enum ReplyRenderer {
    static let version = "reply-render@1"
    static func render(_ raw: String, pack: EvidencePack,
                       context: RenderContext = .empty, isFinal: Bool = true) -> RenderedReply
    enum StreamGranularity { case sentence, word }
    static func stablePrefix(of raw: String, granularity: StreamGranularity) -> String
    static func streamingBody(_ raw: String, pack: EvidencePack,
                              context: RenderContext, granularity: StreamGranularity) -> String
}
```

Pipeline (each step works on text where resolved markers are opaque
private-use placeholders, so no later step can touch an expansion):

1. `OutputSafetyScanner.strippingHarnessMarkup` (as today).
2. Markers → placeholders; unresolvable markers and brace junk dropped.
   Emphasis or quote marks hugging a marker (`*{{quote:1}}*`, `“{{quote:1}}”`)
   are absorbed so the expansion is not double-wrapped.
3. `CitationReconciliation.strippingReferenceMarkers` (as today, now on glue only).
4. Quote-shaped spans in glue — italics `*…*` / `_…_` and quotations `“…”` / `"…"`:
   - verbatim (folded) in a matched slot's `passageText`, ≥ 12 chars →
     **adopted**: replaced by that slot's canonical text from the pack and
     chipped, exactly as if the model had written `{{quote:n}}`;
   - verbatim in what the person said in this chat → kept as a plain curly
     quotation, never italic (italics mean *journal*);
   - quotation-shaped (first-person, or quote-marked with ≥ 4 words) and
     unverifiable → the **enclosing sentence is dropped** (a fabricated
     quotation cannot be repaired into truth);
   - otherwise (short emphasis, scare quotes) → delimiters removed, words kept.
5. Bold survives only on words from an expanded slot's passage (the existing
   Sit rule); otherwise unwrapped.
6. Dates in glue (ISO, `M/D/YYYY`, `Month D[, YYYY]`, `D Month [YYYY]`,
   `Month YYYY`) survive only if they match a pack context date at the
   granularity written, or appear in what the person said. Otherwise the
   date and a leading preposition are removed; never replaced with another
   date. Dates *inside* expansions are the person's words and untouched.
7. `.none` pack: heading lines are dropped (journal form without evidence).
   Any pack: a heading left empty is dropped.
8. Cleanup (spacing, punctuation, empty quote pairs, blank-line runs); if a
   final body has no words left, one authored neutral line
   (`ReplyRenderer.emptyFallback`) is used and `usedFallback` is recorded.
   An empty reply stays empty.

As built: an adopted sentence keeps the passage's own sentence end, so it
never fuses with the next sentence; a dropped quotation keeps its span's
terminator, so only its own sentence goes; a quote already shown is never
repeated (`droppedDuplicateQuoteCount`). The strict passes live in
`ReplyRenderer+Strict.swift` and streaming in `ReplyRenderer+Streaming.swift`.

**Invariants (tested):**

- I1 — `body` never contains `{{`, `}}`, or a placeholder.
- I2 — every italic span in `body` on a `.matched` pack is an expansion of a
  slot, i.e. a folded substring of that slot's `passageText`.
- I3 — `.none` and `.ambient` packs produce **no chips and no citations**, and
  no italic span survives.
- I4 — expansions are byte-identical to pack text (plus the `*` wrapper and
  an ellipsis on clipped quotes).
- I5 — no date survives in glue unless the pack or the person backs it.
- I6 — the renderer never adds journal content: every character of `body`
  is either model glue, pack text, or authored fallback.

**Acceptance:** `ReplyRendererTests` pins each step and invariant with
fixture packs; replaying the renderer over a fabricated-quote fixture drives
`ChatEvalScoring.fabricatedQuotes` to zero while a verbatim expansion is
still scored as a real quote.

### R5. Every Ask reply goes through the renderer, typed and spoken (`REQ-REF-005`)

Wire points in `FoundationModelsIntelligenceService.swift`:

- `finishAskPrep` builds the pack after `RetrievalPolicy.stance` and passes it
  to `buildAskPrompt(…, evidencePack:)`; `AskPreparation` carries `pack` and a
  `RenderContext`. (`buildAskPrompt` derives the same pack itself when called
  without one, so the 14 test call sites keep compiling and the two can never
  drift.)
- `makeResult` renders first; `EpistemicGuard`, `OutputSafetyScanner`, and
  citations all read the rendered body. Citations =
  `CitationReconciliation.citations(for:pack:citedRefs:retrieval:question:)`:
  the entries the body shows (quoted or dated) lead, in the order shown — a
  quoted entry's excerpt is the quote itself — then `reconcileCitations` as a
  backstop, capped at three — **matched packs only**.
- `askStream` — **buffer-then-render, per stable prefix.** Each snapshot is
  cut to a stable prefix (sentence granularity on notebook/thread, word
  granularity on light channels, never inside an open marker, italic, or
  quotation) and rendered with the same pack. Raw model text never reaches
  the bubble or TTS; a whole-reply buffer was rejected because it would
  undo spec 029/032's first-audio work for every turn. The incremental
  output-safety scan and the watchdog are unchanged. A delta whose rendered
  body is empty or unchanged is not yielded, so the thinking state stays up
  until the first settled sentence instead of painting an empty bubble.
  Word granularity can retract a sentence start on a light channel if a
  later fabricated quotation drops that sentence; it never shows the quote.
- The "Reviewed your journals" pre-citations are emitted only for `.matched`.
- `recoverOrdinaryRefusal`'s light retry renders with a `.none` pack.
- `statisticResult` is untouched: it never reaches the model or the renderer.
- A content-free `AppLogger` line records `ReplyRenderStats` per turn.
- `AskPipeline`'s readable map gains the render step.

**Acceptance:** a matched turn's `AskResult.body` contains the pack quote
and no marker; streaming deltas never contain `{{` or an unverified italic;
the statistic channel still returns `promptVersion: "insight-fact@1"`,
`modelIdentifier: "swift"`.

### R6. Chips come from the renderer (`REQ-REF-006`)

`AskResult` gains `chips: [QuoteChip]` and `renderStats: ReplyRenderStats?`
(defaulted, so mocks and fixtures are unchanged). The existing chip surface
— `CitationLink` → `CitationsBottomSheet` → `CitationTimelineList`, fed by
`AskCitation` → `ChatSource.preview` → `JournalCitation.excerpt` — now shows
the exact words the reply quoted, because the renderer's chips lead the
citation list. No SwiftUI view parses italics today, so nothing else
migrates; ambient and none turns show no citations (I3).

**Acceptance:** a persisted turn's `sources[0].preview` equals the rendered
quote; an ambient turn persists no sources.

### R7. Eval hooks and the re-sim plan (`REQ-REF-007`)

`ConversationSimulation` writes `render_version`, `chips` (count), and an
`evidence_pack` object on each assistant row — additive keys, so
`analyze_convo_sim.py` keeps working and can split `hall.fabricatedQuote` by
channel × citation × pack state. The body it scores is already the rendered
body. Keys: `state`, `slots`, `expanded_quotes`, `expanded_dates`,
`adopted_quotes`, `dropped_markers`, `duplicate_quotes`, `stripped_italics`,
`dropped_quotations`, `unwrapped_bold`, `stripped_dates`, `dropped_headings`,
`fallback`.

**Acceptance (run when the Mac lane is online — document, do not block):**

| Metric | Baseline | Target |
|--------|----------|--------|
| Empty-arm gating | 5.5% (Sep 21) | ≤ ~6% — must not regress |
| Persona `hall.fabricatedQuote` | ×911 (Sep 21) | sharp drop, especially thread × cited |
| Nomatch-bait | +18.5pp gating, high invent | no topical quote chips; no citations on miss/ambient |
| `evidence_pack.adopted_quotes` / `dropped_quotations` | — | reported: marker compliance of the 3B model |

## Out of Scope

- Raising `maxEntries` or putting more passages in the prompt (044; the pack
  mirrors the ≤ 5 slice).
- Re-chunking passages or changing the embedding format (044 R1).
- Two-stage retrieval, ANN, multi-query, date/entity prefilters,
  RetrievalGate warehousing (044 P1 retrieval).
- Cloud rerankers or anything outside Z0 (014).
- Live `{{stat:id}}` narration — the grammar exists; `[Computed]` and the
  statistic channel are unchanged (045).
- `TurnClassifier` degeneracy (share / followup / correction); the topical
  inventory stance hole ("what have I written about my dog" grounds on
  ambient rows) — noted for 047/049, not fixed here.
- Relative dates ("three weeks ago", "last Tuesday") in glue — v1 bans only
  absolute dates.
- Rewriting prior assistant turns in the history transcript.
- Feedback warehouse / leave-device paths (042).

## Tasks

The plan landed as PR #34. The implementation is stacked on
`cursor/evidence-pack-renderer-impl-a39c`, in the order the implementation
prompt requires (one housekeeping commit first):

- [x] 0. `spec(050)`: this plan.
- [x] 0b. `fix(intelligence)`: rename the question-shape binding in
      `finishAskPrep` so `main`'s tree compiles (finding 10).
- [x] 1. `evidence-pack`: `EvidencePack` + builder + `QuotedSpanExtractor.candidates`
      + `EvidencePackBuilderTests`. No prompt change. (R1)
- [x] 2. `renderer`: `ReplyRenderer` — placeholders, expansion, chips,
      dropped markers, italic unwrap — + `ReplyRendererTests`. (R4)
- [x] 3. `prompts`: retire the italic contract; legend + `quoted:` removal in
      `buildAskPrompt`; ladder marker copy; exemplar; `ask-core@19`; size gate;
      update `PromptStanceSyncTests`, `AskPromptContractTests`,
      `ConversationalRecallContractTests`, `PromptPersonalizationTests`,
      `PromptRegistryResolutionTests`, `AskPromptSizeTests`. (R2, R3)
      `FailureCorpusTests` needed no edit: its ladder calls use the
      pack-less form, whose copy still differs by rung.
- [x] 4. `ask`: wire the pack and renderer into `ask`, `askStream` (stable
      prefixes), `makeResult`, `recoverOrdinaryRefusal`; the citations
      helper; render log line. (R5)
- [x] 5. `renderer (strict)`: adoption, fabricated-quotation sentence drop,
      conversation allowance, bold verification, date ban, heading drop. (R4)
- [x] 6. `chat`: `AskResult.chips` / `renderStats`; citation chips mirror the
      rendered quote. (R6)
- [x] 7. `eval`: convo-sim `evidence_pack` / `render_version` / `chips`
      fields; this spec's re-sim section; README / ROADMAP registration;
      037 and 049 amendment notes. (R7) `ConversationSimulation.swift`'s
      lone `@testable import withMemento` now matches the `MeetMemento`
      module every other test imports.

## Verification

Scheme and target names below are the ones `project.pbxproj` declares
(`MeetMemento` / `MeetMementoTests`); see finding 14 before running them on a
fresh checkout.

- [ ] `xcodebuild test -scheme MeetMemento -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
      -only-testing:MeetMementoTests/EvidencePackBuilderTests
      -only-testing:MeetMementoTests/ReplyRendererTests
      -only-testing:MeetMementoTests/PromptStanceSyncTests
      -only-testing:MeetMementoTests/AskPromptContractTests
      -only-testing:MeetMementoTests/AskPromptSizeTests
      -only-testing:MeetMementoTests/ConversationalRecallContractTests
      -only-testing:MeetMementoTests/PromptContradictionTests
      -only-testing:MeetMementoTests/FailureCorpusTests` green.
- [ ] Full online suite per `.github/PULL_REQUEST_TEMPLATE.md`.
- [x] `scripts/ci/check_single_intelligence_importer.sh` still reports exactly 1.
- [x] `scripts/ci/check_no_hardcoded_context_budgets.sh` passes (the one new
      clip, a month-name abbreviation, carries a `budget-exempt` note).
- [ ] Re-sim (Mac, when online) — see "Re-running the study" below.

### What was verified without a Mac (2026-09-22)

The Mac runners were offline, so the pure-Swift half was compiled and run on
a Linux Swift 6.2 toolchain: a scratch SwiftPM package whose sources are the
real repo files (the Intelligence layer's Foundation-only files, `Entry`,
`ThemeCatalog`, `LocalProfileStore`, `ModelRouter`, `AskTranscriptPlan` over
a SHA-256 shim) plus the pure sections of `EntryRetriever.swift` and
`FoundationModelsIntelligenceService.swift` extracted verbatim — the result
types, the context block, `buildAskPrompt`, `stanceMatchingEvidence`, and the
citation statics. It ran 230 tests from 15 real test files, all green:
`EvidencePackBuilderTests`, `ReplyRendererTests`, `PromptStanceSyncTests`,
`AskPromptContractTests`, `AskPromptSizeTests` (red on `main`, green here),
`ConversationalRecallContractTests`, `PromptContradictionTests`,
`ReferenceMarkerStrippingTests`, `PromptPersonalizationTests`,
`PromptRegistryResolutionTests`, `TurnShapeCadenceTests`,
`ConversationalMoveTests`, `ReplyChannelTests`, `RetrievalPolicyTests`,
`AskPipelineTests`, and `ChatEvalScoring` as a helper. SwiftLint `--strict`
is clean on every new app file; the files this change edits report only
violations `main` already has.

Mac-only, not run: anything importing FoundationModels, UIKit, SwiftUI or
NaturalLanguage — the live `ask` / `askStream` / `makeResult` wiring (checked
by reading, and by the harness compiling every API it calls),
`FailureCorpusTests` and `ResponsePolicyTests` (need the NaturalLanguage
retriever), `AskTranscriptPlanTests` (needs `ChatService`), the chat UI, and
the convo-sim itself.

### Re-running the study

On the build Mac (iOS 27 simulator, Apple Intelligence on), with this branch
checked out. `main`'s `ConversationSimulation` knows the `empty` and `cold`
arms; the 262-entry `persona` arm lives on `study2-persona-arm` (`fd294a3`,
not pushed), so the persona comparison needs this branch rebased onto — or
cherry-picked into — that branch first. Variables follow the file's own
`TEST_RUNNER_` convention:

```bash
# Empty arm (the regression guard) + persona arm, 100 conversations each
TEST_RUNNER_CONVO_SIM=1 TEST_RUNNER_CONVO_SIM_ARMS=empty,persona \
TEST_RUNNER_CONVO_SIM_LABEL=evidence-pack-050 \
DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test -scheme withMemento \
  -destination 'platform=iOS Simulator,id=<iOS 27 device>' \
  -parallel-testing-enabled NO \
  -only-testing:MeetMementoTests/ConversationSimulation
python3 analyze_convo_sim.py .eval-runs/convo-sim/evidence-pack-050.jsonl --check-046
```

Compare against `full-2026-09-21-persona.jsonl` (persona) and the Sep 21
empty arm (5.5% gating). Read the new `evidence_pack` fields before the
headline: a high `dropped_quotations` beside a low `hall.fabricatedQuote`
means the renderer is doing the model's job, and the legend needs another
pass; a high `adopted_quotes` means the model copies legend text instead of
writing markers, which is safe but worth tightening.

## Risks

| Risk | Mitigation |
|------|------------|
| `main` does not compile and fails the size gate before this work starts | Commit 0b fixes the redeclaration; the R3 rewrite is sized under the gate. Both called out in the PR. |
| The project file and CI still point at `MeetMemento/` (finding 14), and the Mac runners are offline, so no lane here can build the app | Pure-Swift units (pack, renderer, prompt assembly, stance/registry) are compiled and unit-tested on a Linux Swift 6.2 toolchain against the real source files; everything that needs FoundationModels or UIKit is left to the Mac lane and listed as such in the PR. |
| R1/R3/R4 local-branch work is not on `main` | Build on main's actual semantics (finding 12); nothing here reintroduces "ambient → grounded". |
| The 3B model ignores markers and keeps writing italics (in-context imitation of its own earlier, rendered replies) | Adoption turns verbatim spans into real expansions; unverifiable ones are dropped; `adopted_quotes` / `dropped_quotations` make compliance measurable. |
| Guided decoding and braces | `{{…}}` is ordinary string content in `@Generable` string fields; a malformed marker is dropped, never shown. |
| Sentence-granular streaming adds first-sentence latency on journal channels | Bounded to one sentence; light channels stream per word; a whole-reply buffer (the other option) would cost the full generation. |
| Word-granular light-channel streaming may retract a sentence start when a later fabricated quotation drops its sentence | Rare (light prompts carry no evidence and forbid markdown); only glue is retracted, never a quote. |
| Over-stripping legitimate emphasis or quotations | Short emphasis is unwrapped, not dropped; conversation quotes are kept; only first-person / long quote-marked unverifiable spans drop a sentence. |
| Dropping a sentence can remove the closing question | Accepted: a reply without an Open is better than a fabricated quote; measured by `rule.noOpen`. |
| Ambient inventory turns ("what have I been writing about?") lose their citation link | Deliberate (R6/I3): ambient is not a topical citation. A recent-entries affordance is a follow-up. |
| Empty-arm regression | Empty archive never reaches notebook/thread (046 R3, unchanged); the renderer only removes form on `.none` packs, which is what the empty-arm scorers already penalise. |

## Follow-ups (not this spec)

- Two-stage retrieval, date/entity prefilters, multi-query union, ANN past
  ~1k passages, RetrievalGate warehousing (044 P1).
- Stance: a topical inventory question over ambient retrieval should be
  `.noMatch`, not `.journalGrounded` (nomatch-bait).
- Relative-date verification; live `{{stat:id}}` for `[Computed]` facts.
- Exercise dead classifiers (acknowledgement, reflectiveQuestion,
  correction) in the sim; changelog `TurnType` / `ReplyChannel` between
  study branches.
- Optional: rewrite rendered quotes in history turns so the model stops
  imitating italics it can no longer use.

## Regression Guards

- **`REQ-INT-001` / CONSTITUTION §4 rule 5** — the pack and renderer are plain
  Swift; `check_single_intelligence_importer.sh` still reports 1.
- **CONSTITUTION §4 rule 3** — the render log line is counters only: no quote,
  body, or query text.
- **046 R3/R4** — an empty archive still never resolves to notebook/thread and
  still decodes `LightAskAnswer`.
- **046 finding 8** — a citation for an entry not placed in context still
  cannot exist; the renderer only narrows citations further.
- **045 R5** — the statistic channel skips AFM and the renderer.
- **044** — theme boost stays reorder-only; `maxEntries` stays 5; passages
  are not re-chunked.
- **029 Amendment A / 032** — `body` still leads decode order; streaming
  still streams; narration never receives a marker.
- **037 voice** — Meet / Notebook / Sit / Open stays; the notebook moment is
  still a dated heading and their own words, now inserted by Swift.
