---
id: 046
title: Grounding and Evidence Discipline — Withhold the Form When There Is No Evidence
tier: P1
status: draft (2026-09-20)
effort: 5–6 sessions; R1/R2 ship independently of the rest
depends_on: [017, 022, 037, 039, 044]
findings:
  - fabrication-scorer-never-compiled
  - regex-scorer-failure-is-silent
  - quote-scorers-vacuous-without-corpus
  - channel-resolved-before-evidence-is-known
  - notebook-voice-without-evidence
  - fabricated-entries-on-empty-archive
  - schema-grants-form-prompt-withdraws-it
source_refs: [REQ-EVD-001, REQ-EVD-002, REQ-EVD-003, REQ-EVD-004, REQ-EVD-005, REQ-EVD-006, REQ-INT-001, REQ-INT-017, REQ-PRM-004, REQ-SUR-003]
tech_refs: [technology/01-foundation-models.md, technology/04-evaluations.md]
---

# 046 — Grounding and Evidence Discipline

**Traceability:** tightens the Ask pipeline that spec
[`017`](017-intelligence-boundary-and-prompt-architecture.md) owns and spec
[`039`](039-reply-channels-and-phatic-generation.md) channels, without moving the
boundary. Notebook voice and the Meet / Notebook / Sit / Open recipe remain
[`037`](037-conversational-recall-experience.md); retrieval quality remains
[`044`](044-agentic-harness-depth.md) R1–R3; eval mechanics remain
[`022`](022-evaluation-and-quality-study.md) with run identity from
[`043`](043-eval-run-warehouse.md). This spec mints the **`REQ-EVD-`** series inline
(the `REQ-NAR-` / `REQ-PERF-` pattern — self-contained, no edit to
`memento-2.0-architecture-spec.md`).

**Does not implement:** the bounded tool loop or a second retrieval hop
(`044` R4 — `SearchJournalTool` exists but is wired off); the living profile
(`044` R6); follow-up and correction routing, which is
[`047`](047-conversational-state.md); the harness that measures all of this, which is
[`048`](048-harness-depth-ii.md). The `statistic` channel is untouched — it is already
fully evidence-typed by construction (`InsightFact.supportingEntryIDs`,
`modelIdentifier: "swift"`, empty body).

## Why

A 200-conversation study (2026-09-20; 6,984 messages across a cold-start journal and
a **zero-entry** journal) found the app inventing journal entries for a person who
has written nothing: 13.1% of zero-entry generated turns present invented entry
content in italic spans or `###` headings, *after* correctly saying it sees nothing.
The gating scorer built to catch precisely this — `hall.fabricatedQuote`, whose own
doc comment calls it "the single most damaging failure mode for a journal app" — has
never executed, because its regex cannot compile and the failure is swallowed.

Two causes, both instances of the same rule being broken. **The form is granted
before the evidence is known**: `ReplyChannel.resolve` cannot see whether the archive
is empty, so a journal question against an empty store still selects notebook voice
and the schema that authorises headings and journal quotation — then the prompt asks
the model to restrain itself. And **a check that cannot run reads as a pass**. Both
violate *code decides, the model renders* (`037` / `039` / `044`).

Tier P1: a journaling app that fabricates journal entries damages the product's
central promise, and the detector for it is currently disabled.

## Technology References

- `technology/01-foundation-models.md` §4 — guided generation and
  `@Generable` / `@Guide` semantics; a `@Guide` description is a *request*, not a
  constraint the runtime enforces. Any rule that must hold has to be expressed as
  schema selection or post-generation reconciliation, not as guide prose.
- `technology/01-foundation-models.md` §3 — `contextSize` / `tokenCount(for:)`;
  unchanged by this spec, listed because R4 alters which schema is decoded and
  therefore the response budget path (`ReplyChannel.maximumResponseTokens`).
- `technology/04-evaluations.md` — gate posture: measure first, threshold after.
  R1 restores a gate that has never fired; it lands **report-only** and is re-armed
  only after two warehoused runs (`022` / `043`).

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Verified 2026-09-20
> against branch `convo-sim-harness`, prompt `ask-core@17`, on an iOS 27.0 simulator.
> Percentages are computed over the 3,119 model-generated assistant turns in
> `.eval-runs/convo-sim/full-2026-09-20.jsonl` (excluding 143 Swift-computed
> `statistic` turns and 230 error turns). The study's simulated *person* is a 3B
> model playing a persona brief, so rates are directional; rows 1, 2, 3 and 5 are
> structural and do not depend on the person being human.

| # | Finding | Evidence | Severity |
|---|---------|----------|----------|
| 1 | **`hall.fabricatedQuote` has never executed.** The pattern is a Swift raw string containing `\u{201C}`; raw strings do not process backslash escapes, so NSRegularExpression receives those characters literally, and ICU accepts `\uhhhh` / `\x{hhhh}` but not `\u{…}`. Confirmed at runtime: `NSRegularExpression(pattern:)` throws `The value "…" is invalid`; the same pattern with `\x{201C}` compiles and matches. | `ChatEvalScoring.swift:236` (pattern), `:221` (`spans` swallows via `try?`) | **Critical** |
| 2 | **A regex scorer that fails to compile returns `[]` silently.** `spans()` is `guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }`. There is no assertion anywhere that a scorer's pattern compiles, and no positive fixture proving any `hall.*` scorer fires. | `ChatEvalScoring.swift:220-224` | **Critical** |
| 3 | **Empty-corpus behaviour of the quote scorers is emergent, not specified.** `QuoteIndex([])` leaves `haystack == ""` and `grams` empty, so `contains` is constant-false and `quotesCorpus` returns `nil` unconditionally. `hall.uncitedQuote` therefore *cannot* fire with no entries; `fabricatedQuotes` and `boldNotTheirWords` invert into hair-triggers that would flag every span. Measured: `hall.uncitedQuote` 0 on the empty arm vs 7 on cold. | `ChatEvalScoring.swift:44-65` (`QuoteIndex.init`), `:73-76`, `:81-95`, `:247-251`, `:317-327` | High |
| 4 | **Channel is resolved before retrieval, from the turn type alone.** `ReplyChannel.resolve(turn:hasImages:)` has no evidence parameter, so a `journalQuery` against an empty store resolves to `notebook`. Measured: 36.8% of zero-entry turns (588/1,597) routed to `notebook`. | `FoundationModelsIntelligenceService.swift:924`, `ReplyChannel.swift:27-39` | High |
| 5 | **Notebook voice with no evidence is the worst cell in the matrix.** Violation rate 38.3% (`notebook`/empty) vs 20.5% (`notebook`/cold) vs 6.8% (`companion`/empty) and 9.5% (`companion`/cold). It is also the slowest: 2.98s p50 vs 1.67s for `companion`/empty. | `.eval-runs/convo-sim/full-2026-09-20.jsonl`, grouped by `arm` × `channel` | High |
| 6 | **The schema grants the form; the prompt then asks for restraint.** `AskAnswer.body`'s `@Guide` reads "Notebook, ###, and italic quotes only if this turn uses the journal" — a self-assessment delegated to a ~3B model. The pipeline already knows the answer: `archiveEmpty` is a `buildAskPrompt` parameter and emits `[No journal entries in the archive]`. | `FoundationModelsIntelligenceService.swift:56-90` (`AskAnswer`), `:2059-2064` (`archiveEmpty` branch), `RetrievalPolicy.swift:86-93` (`.noMatch` promptLine) | High |
| 7 | **Fabricated entry content on an empty archive.** 13.1% of zero-entry generated turns (212/1,597) carry an italic span ≥12 characters or a `###` heading presenting invented journal material; 202 of those match the *intended* `fabricatedQuotes` pattern exactly, and none was flagged by it. | `.eval-runs/convo-sim/full-2026-09-20.jsonl`; reproduce with the pattern in row 1 | **Critical** |
| 8 | **An invented citation *ref* is already impossible.** `reconcileCitations` filters `refs` to those present in `byRef`, built from the entries actually placed in context. Prose fabrication is the uncovered half, not citation fabrication. | `FoundationModelsIntelligenceService.swift:2265-2291` | — (guard to preserve) |

## Requirements

**Traceability:** R1–R2 → `REQ-EVD-001`/`002` (detection integrity); R3–R4 →
`REQ-EVD-003`/`004` (evidence decides the form); R5 → `REQ-EVD-005` (typed claims);
R6 → `REQ-EVD-006` (prompt contract). R1–R2 are test-target only and ship without
touching the app.

**Zone tag:** every requirement here is Z0 (on-device). No requirement changes what
leaves the device; `REQ-PRIV-001` is untouched.

### R1. The fabrication scorer runs, and a scorer can never again fail silently (`REQ-EVD-001`)

Repair the pattern so ICU accepts it (`\x{201C}` / `\x{201D}`, or a non-raw literal
with real escapes). Then fix the class of defect rather than the instance: `spans()`
converts a programming error into a permanent silent pass, and nothing in the suite
would ever report it.

Every regex-backed scorer gains (a) a test that its pattern compiles, and (b) at
least one positive fixture that makes it emit. A gating check that cannot fire is
worse than no check, because it reads as a pass.

`hall.fabricatedQuote` lands **report-only** until two runs are warehoused
(`022` / `043`), because repairing it will surface violations on the cold arm that
were previously invisible. That is detection appearing, not quality regressing.

**Acceptance:**
- Given the repaired pattern, when `hall.fabricatedQuote` is replayed over
  `.eval-runs/convo-sim/full-2026-09-20.jsonl`, then it fires on the 202 empty-arm
  turns carrying a matching span, and on zero turns carrying no italic span.
- Given any scorer in `ChatEvalScoring` whose pattern fails to compile, when the unit
  suite runs, then a test fails and names that scorer.
- Given each `hall.*` and `rule.*` regex scorer, then a positive fixture exists that
  makes it emit exactly its own code.
- Given `ChatEvalGate` after two warehoused runs, when the threshold is armed, then
  `hall.fabricatedQuote` gates (it already carries a gating prefix in
  `ChatEvalScoring.gating`).

### R2. Empty-corpus semantics are specified, not emergent (`REQ-EVD-002`)

Define the zero-entry case explicitly for every corpus-consulting scorer:

> A span presented as journal material must resolve to an entry. Where no entries
> exist, every such span is fabricated by construction.

This rule needs no `QuoteIndex` and no corpus to diff against, which is precisely why
it works where the current checks cannot. Reuse the existing Swift-side verbatim
matcher `quotedRefs(in:retrieval:)`
(`FoundationModelsIntelligenceService.swift:2300`) rather than adding a second
quote-matching implementation.

**Acceptance:**
- Given `QuoteIndex([])`, when `contains`, `quotesCorpus`, `fabricatedQuotes`,
  `uncitedQuote` and `boldNotTheirWords` are each exercised, then behaviour is pinned
  by a fixture rather than emerging from an empty haystack.
- Given an empty archive and a reply containing an italic span, then a violation is
  emitted without consulting a corpus.
- Given an empty archive and a reply containing no italic span, bold span or heading,
  then no corpus-fidelity violation is emitted.

### R3. Evidence state is decided before the channel (`REQ-EVD-003`)

Introduce an explicit evidence state computed by code —
`.none` (archive empty) / `.ambient` (entries exist, no topical match) /
`.matched` — and make channel resolution a function of turn type **and** evidence
state. A turn against an empty archive must never resolve to `notebook` or `thread`.

The information already exists and is already consulted, just too late:
`RetrievalResult.isEmpty` / `.isAmbient`, and `stanceMatchingEvidence`
(`FoundationModelsIntelligenceService.swift:1928`) which performs exactly this
reconciliation for the *stance* after the channel is fixed. R3 moves the decision
earlier and lets `stanceMatchingEvidence` become a no-op rather than a corrector.

Ordering constraint: the archive-empty test needs no retrieval and must run at
classification time; the `.ambient` / `.matched` distinction is only knowable after
`retrieveWide`, so channel resolution for a non-empty archive may refine once
retrieval returns. Refinement must never *upgrade* into `notebook` — only downgrade
out of it.

**Acceptance:**
- Given a store with zero entries, when any turn classifies as `journalQuery`, then
  the resolved channel is never `notebook` and never `thread`.
- Given a non-empty archive with ambient-only retrieval, when the prompt is built,
  then the stance and channel are already consistent and
  `stanceMatchingEvidence` changes nothing.

**Amendment (2026-09-21, spec 049).** Delete the `nearbyOnly` instruction
that tells the model the closest entry is not the answer and then quotes
it. That sentence made every broad-recall and every "last Tuesday" opener
cite an entry and deny it. Inventory with any hits uses the `exact` or
`strong` rung. A true miss is rung `none` and does not quote a nearest
entry. "I don't see anything from that stretch" is legal only on rung
`none`.
- Given `DiagTurnRouting`, when run, then its table reports the evidence state
  alongside the channel for every row.
- Given a fresh 100-conversation zero-entry arm (`048` R5), when measured, then its
  violation rate is at or below the measured `companion`/empty baseline of 6.8%.

### R4. The form is withheld by code, not requested by prompt (`REQ-EVD-004`)

When evidence state is `.none`, decode the body-only schema (`LightAskAnswer`) so the
notebook grammar — `###`, italic journal quotes, `citedRefs` — is never offered to the
model at all. The mechanism already exists and is already used for spoken narration:
`ReplyChannel.usesBodyOnlySchema(spoken:)` (`ReplyChannel.swift:103`) and the
`respondToAsk` branch (`FoundationModelsIntelligenceService.swift:1322`). This
requirement makes that switch evidence-aware in addition to spokenness-aware.

Delete the self-restricting clause *"only if this turn uses the journal"* from
`AskAnswer.body`'s `@Guide`: with R3 in place the schema is only ever offered when the
turn does use the journal, so the clause is both redundant and an invitation to
self-assess.

**Acceptance:**
- Given an empty archive, when a reply is generated, then it is decoded from
  `LightAskAnswer`, and the rendered body contains no `###`, no italic span and no
  citations.
- Given `AskPromptContractTests`, when R4 lands, then its `@Guide` assertions are
  updated in the same PR and `test_spokenNotebook_usesBodyOnlySchema` still passes.
- Given a non-empty archive with a topical match, then `AskAnswer` is still decoded
  and citation behaviour is unchanged.

### R5. Evidence-typed claims (`REQ-EVD-005`)

Extend the Ask answer so assertions carry either a resolvable evidence reference or
an explicit interpretation marker, and reconcile them the way `AskCitation` values are
already reconciled. An explicit-fact claim with no resolvable evidence is then
detectable with no corpus to diff against — the same property R2 gives the scorers,
but inside the contract rather than outside it.

**This converges on an existing reference implementation rather than inventing one.**
`EntryReflection` and `PeriodReflection` already carry `groundedEntryIDs: [String]`
with the guide rule "Every claim must trace to one of these"
(`FoundationModelsIntelligenceService.swift:148-175`). CONSTITUTION §3 prefers
converging on the reference implementation over a parallel system.

Hard design constraint, from measured data already recorded in the source:
`citedRefs` is **deliberately optional** because making it required dropped decode
success from 5/5 to 4/5 (`:69-84`). Any field added here is optional and trailing,
with a Swift-side fallback, so a decode failure costs evidence metadata and never
body text. Field order is decode order — `body` leads so first-token latency is
unaffected (`029` Amendment A).

**Acceptance:**
- Given a store with zero entries, when a reply asserts a fact carrying no resolvable
  evidence reference, then the pipeline detects it without consulting a corpus.
- Given a decode that drops the new field entirely, when the turn completes, then the
  body still renders and the turn is recorded as *unverified*, never failed.
- Given `AskLatencyFloorTests`, when R5 lands, then first-token latency is unchanged
  within its existing tolerance.
- Given an evidence reference naming an entry that was not placed in context, then it
  is dropped exactly as an invented `citedRef` is today.

### R6. Prompt version bump and contract sync (`REQ-EVD-006`)

`ask-core@17` → `ask-core@18` (and `ask-degraded@17` → `@18`). Contract tests update
in the same PR as the behaviour, never later — the standing rule from
`044-045-implementation-sessions.md`.

**Acceptance:** given R4 or R5 landing, then `AskPromptContractTests`,
`PromptStanceSyncTests` and `PromptRegistryResolutionTests` are updated in that same
PR, and `PromptRegistryResolutionTests`' exhaustive
`GenerationIntent.allCases × zones × degraded` sweep still resolves for every
combination.

## Out of Scope

- The bounded tool loop and second retrieval hop — `044` R4.
- The living profile / lens refresh — `044` R6.
- Follow-up and correction routing — [`047`](047-conversational-state.md).
- Counterfactual worlds, route coverage, the failure corpus and the standing
  long-form harness — [`048`](048-harness-depth-ii.md).
- Retrieval ranking quality — `044` R1–R3, already landed.
- The `statistic` channel, already evidence-typed by construction.

## Tasks

- [ ] 1. Repair the `fabricatedQuotes` pattern; add a compile assertion for every
      regex scorer and a positive fixture per `hall.*` / `rule.*` code. (R1)
- [ ] 2. Replay the repaired scorer over the archived run; record the delta in the PR
      body; leave `hall.fabricatedQuote` report-only. (R1)
- [ ] 3. Pin empty-corpus behaviour for every corpus-consulting scorer with fixtures;
      implement the "no entries ⇒ every journal-material span is fabricated" rule
      reusing `quotedRefs`. (R2)
- [ ] 4. Introduce the evidence state; thread it into `ReplyChannel.resolve`; make
      `stanceMatchingEvidence` a no-op for the empty-archive case. (R3)
- [ ] 5. Make `usesBodyOnlySchema` evidence-aware; strip the self-restricting clause
      from `AskAnswer.body`'s `@Guide`. (R4)
- [ ] 6. Add the evidence-reference field to the Ask schema, optional and trailing,
      with reconciliation and a Swift-side fallback. (R5)
- [ ] 7. Bump `ask-core@17` → `@18`; update the three prompt test files. (R6)
- [ ] 8. Register in `specs/README.md` and `ROADMAP.md`. (—)

## Verification

- [ ] `xcodebuild test -only-testing:withMementoTests/ChatEvalScoringTests` — every
      scorer compiles and every `hall.*` / `rule.*` code has a firing fixture.
- [ ] Replay check: the repaired `hall.fabricatedQuote` fires on 202 empty-arm turns
      of `.eval-runs/convo-sim/full-2026-09-20.jsonl` and on no turn without an
      italic span.
- [ ] Runtime confirmation of finding 1 (already performed 2026-09-20, repeat if the
      pattern is touched): `NSRegularExpression(pattern:)` throws on the current
      string and compiles with `\x{201C}`.
- [ ] `xcodebuild test -only-testing:withMementoTests/AskPromptContractTests
      -only-testing:withMementoTests/PromptStanceSyncTests
      -only-testing:withMementoTests/PromptRegistryResolutionTests` green after R4–R6.
- [ ] `scripts/ci/check_single_intelligence_importer.sh` still reports exactly 1.
- [ ] `scripts/ci/check_no_hardcoded_context_budgets.sh` still passes.
- [ ] A fresh zero-entry arm via `048` R5 measures a violation rate ≤ 6.8%, and its
      `notebook` share is 0%.
- [ ] `AskLatencyFloorTests` green — R5 must not move first-token latency.

## Regression Guards

- **P3 / `REQ-INT-001`** — exactly one module imports `FoundationModels`. The
  evidence-reference field and any schema change live in
  `FoundationModelsIntelligenceService.swift`; the evidence state itself is a plain
  Swift type and must not require a second importer.
- **`reconcileCitations`' existing guarantee** — a citation whose ref was not placed
  in context can never survive. R5 extends this to prose claims; it must not weaken it.
- **Spec 029 Amendment A** — `body` leads the decode order so first-token latency
  never waits on trailing metadata.
- **Spec 039 channel budgets** — `ReplyChannel.maximumResponseTokens` and
  `temperature(retrievalRan:)` semantics are unchanged; R4 changes which schema is
  decoded, not the budget table.
- **Spec 037 rule 3 / 045 R1** — the model never counts. Nothing here reintroduces a
  model-authored number.
- **CONSTITUTION §4 rule 3** — content-free logs. The evidence state may be logged;
  entry text, spans and query text may not.
- **Measure first, threshold after** (`technology/04-evaluations.md`) — R1's restored
  scorer lands report-only and is armed only after two warehoused runs.
