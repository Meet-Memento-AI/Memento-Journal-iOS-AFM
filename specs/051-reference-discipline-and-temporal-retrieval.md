---
id: 051
title: Reference Discipline II and Temporal Retrieval — Close the Study III Residuals
tier: P1
status: draft (2026-09-23)
effort: 2–3 sessions, stacked commits (see Tasks)
depends_on: [022, 037, 044, 045, 046, 048, 049, 050]
findings:
  - marker-grammar-taught-when-there-is-nothing-to-point-at
  - prompt-scaffolding-reaches-the-screen
  - asserted-dates-are-unscored-and-rose
  - evidence-slots-are-mostly-noise-and-the-model-declines-them
  - origin-questions-suppress-recency-but-never-prefer-the-earliest
  - origin-cue-list-has-holes
  - within-window-ranking-is-weak
  - retrieval-tuning-was-fitted-on-the-only-gold-set
source_refs: [REQ-REF-008, REQ-REF-009, REQ-EVD-007, REQ-RET-001, REQ-RET-002, REQ-RET-003, REQ-INT-001]
tech_refs: [technology/01-foundation-models.md, technology/04-evaluations.md]
---

# 051 — Reference Discipline II and Temporal Retrieval

**Traceability:** closes the residuals [`050`](050-evidence-pack-and-reply-renderer.md)
left behind, measured by its own re-sim (Study III). Keeps 050's invariant — code owns
the reference, the model owns the glue — and extends it to the case 050 did not cover:
what the prompt should say when there is nothing to point at. Retrieval requirements
extend [`044`](044-agentic-harness-depth.md) R2's gate with the misses it measured.
Mints **`REQ-REF-008/009`**, **`REQ-EVD-007`**, **`REQ-RET-001/002/003`**.

**Does not implement:** `periodSummary` / `periodCompare`. Those are a product
capability, not hallucination control, and belong in their own spec once this one is
closed.

## Why

Spec 050 worked. Invented material on the 262-entry journal fell **56.6% → 2.0%**,
fabricated quotations **911 → 0**, at no latency cost. It is the second time in this
series that taking a decision away from the model produced the largest movement
available, after channel selection took journal voice on an empty archive from 36.8% to
zero.

Study III was pre-registered before it ran (`eval-archive/STUDY_III_PREREGISTRATION.md`,
committed at `1689c22`). Five of seven predictions were met. The two that failed both
landed on the report that made them, and the important one is P4.

The 2026-09-22 report argued that a ~3B decoder cannot verify a reference against a
store, so it would keep emitting unverifiable references and the renderer would be all
that restrained it — cleanup predicted on ≥25% of seeded turns. **The renderer
intervened on 2.4%.** Told to point rather than to italicise, the model largely stopped
reaching for the old vehicle. The limit was not capacity; it was the contract. Italics
mean emphasis throughout the model's training distribution, and a rule redefining them
on every turn was never going to hold. A typed marker works because nothing else claims
the token.

That correction is what this spec is built on. Where 050 succeeded by removing an
overloaded contract, the remaining defects are the same shape: a grammar taught where
it cannot apply, a renderer that does not strip its own furniture, and a reference class
(dates) with no check at all. None of them needs a larger model.

The retrieval half exists because a competing hypothesis — that the residuals persist
because 3B is the ceiling and finer chunking would fix RAG — was tested rather than
argued. `RetrievalGate` gave **recall@5 = 0.760**: real headroom, but concentrated in
first-mention and within-window ranking, not in passage granularity.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Verified 2026-09-23
> against Study III (`eval-archive/convo-sim/full-2026-09-23-resim.jsonl`, 6,858
> messages) and `eval-archive/retrieval-baseline-2026-09-23.json`.

| # | Finding | Evidence | Severity |
|---|---------|----------|----------|
| 1 | **The marker grammar is taught when there is nothing to point at.** `ask-core@19` defines `{{quote:N}}` / `{{date:N}}` unconditionally; `EvidencePack.noneNote` then says "not this turn". The model emitted markers against an empty pack on **184 turns, 237 markers**. With a pack, it mis-resolved **2 markers in 3,157 slots** — so this is not an indexing weakness, it is a negative instruction failing. | `Prompt/PromptRegistry.swift:445`, `:492-493`; `Evidence/EvidencePack.swift:99` | **High** |
| 2 | **Prompt scaffolding reaches the screen.** 34 leaks on the seeded arm — `leak.placeholder` 24, `leak.promptTag` 8, `leak.sectionLabel` 2 — including `[Evidence]: none` in user-visible text. **Zero** across 6,505 generated turns in the two prior studies. The renderer is specified as the single choke point for Ask bodies and does not strip its own furniture. | `Reconciliation/ReplyRenderer.swift:90-108` | **High** — the only outright regression |
| 3 | **Asserted dates are unscored, and rose.** Seeded-arm month-and-day assertions went **118 → 290** (7.3% → 17.5%); **250 pass every check**. `{{date:N}}` made dating salient and nothing measures it. 046's own motivating example — a dated entry cited on an arm with no journal — carries an empty `violations` array in the 2026-09-20 archive. | `Eval/ChatEvalScoring.swift` (no date scorer) | **High** |
| 4 | **Evidence slots are mostly noise and the model declines them.** ~1.1 of 5 slots are the answer on a typical gold question; the model expanded a quote marker on **100 of 641** matched turns (15.6%). A model handed four parts noise to one part signal and declining to point may be calibrated, not disobedient. No numeric confidence crosses the `RetrievalResult` boundary, so narrowing `k` is not currently expressible. | `Retrieval/EntryRetriever.swift:42-54`, `:179` | Medium |
| 5 | **Origin questions suppress recency but never prefer the earliest.** `seeksOrigin` fires on "When did I **start** pottery classes?" and the query still misses: expected `e-2026-01-08-1`, returned `01-29, 04-16, 04-30, 05-14, 07-02`. Zeroing recency removes a bias; it adds none. | `Retrieval/EntryRetriever.swift:978-998`, `:483` | Medium |
| 6 | **The origin cue list has holes.** "How did my **first** pottery class go?" and "When did Sam and I **break up**?" never reach `seeksOrigin` — the list carries `first said/say/time/mention/wrote/write` but not bare `first` before a noun, and no life-event verbs. Both miss. | `Retrieval/EntryRetriever.swift:983-991` | Medium |
| 7 | **Within-window ranking is weak; the window filter is fine.** For "What was I working on last December?" all five returned entries are 2025-12 — the filter works. It returns `12-04, 12-02, 12-10, 12-16, 12-01`; the answer is `12-05`. Inside an already-constrained set the σ significance bar is doing redundant work. | `Retrieval/EntryRetriever.swift:490-491`, `:777-790` | Medium |
| 8 | **Retrieval tuning was fitted on the only gold set.** 45 questions, weights already fitted, and `RETRIEVER_GRID=1` exists to fit them further. Any gain measured on the same set is overfitting; temporal is 11 questions. | `Eval/RetrievalGate.swift:47-52`; `Fixtures/gold/` | **High** (methodological) |
| 9 | **`.nearbyOnly` has consumers but no producer.** Declared and given prompt copy, handled in four files, and `RetrievalPolicy.swift:229` routes ambient non-inventory to `.noMatch` instead. Dead branch. | `Retrieval/RetrievalPolicy.swift:48` vs `:229` | — (recorded, not fixed here) |
| 10 | **Passages are the unit of similarity; entries the unit of ranking.** Two strong passages in one entry cannot occupy two slots. This is the mechanism that makes chunk size the wrong lever for findings 5–7. | `Retrieval/EntryRetriever.swift:669-711` | — (constraint) |

## Requirements

**Traceability:** R1 → `REQ-REF-008`; R2 → `REQ-REF-009`; R3 → `REQ-EVD-007`;
R4 → `REQ-RET-001`; R5 → `REQ-RET-002`; R6 → `REQ-RET-003`.

### R1. Do not prohibit a grammar; state the absence (`REQ-REF-008`)

**Amended 2026-09-23, during implementation.** The requirement first read "when the
pack is `none`, the marker grammar is absent from the prompt". Reading the code showed
that is the wrong trade, and the amendment is recorded rather than the requirement
quietly reshaped.

Three facts moved it:

1. **The harm is not user-visible.** The 237 phantom markers are dropped by
   `ReplyRenderer` and `RenderText.tidy` closes the gap. Inspecting the rendered
   bodies from Study III, none carries a hole or a damaged sentence. The cost is
   wasted tokens and a model ignoring an instruction — real, but not a defect a
   reader meets.
2. **The grammar is taught in eight places, not two** — `askCore`,
   `askCoreDegraded`, four channel suffixes, `TurnStance` prompt lines, and the
   `AskAnswer` `@Guide` schema description, which is structural and always present.
3. **The instructions are speculatively prefilled** (`PromptRegistry.swift:567`) and
   `PromptStanceSyncTests` exists to assert they stay aware of *every* stance a
   channel can produce — the notebook suffix already carries its own
   `[Turn: journal question, no matches]` branch. Alternating two instruction
   variants per turn would thrash the prefill cache on every turn, to fix something
   the renderer already absorbs.

So the requirement narrows to the part that is turn-local and free: the pack notes
**state the absence and stop**, rather than prohibiting a grammar the instructions
have already taught. `noneNote` becomes `[Evidence: none.]`; `ambientNote` keeps its
positive direction and drops its prohibitions. The guarantee is not weakened, it is
relocated to where it actually holds — `ReplyRenderer` drops an unbacked marker
whatever the prompt said.

The general lesson survives intact and is the one 050 established: a negative
instruction is not a mechanism. What changed is where the mechanism belongs.

**Acceptance:**
- Given any pack state, the note states what evidence exists and asks for nothing.
- Given an unbacked marker, the renderer drops it regardless of prompt wording —
  already pinned by `test_markersOnANonePack_areAllDropped`.
- `AskPromptContractTests` and `EvidencePackBuilderTests` reference the constants by
  name and stay green without edits.

**Deliberately not done:** removing the grammar from the cached instruction surface.
Recorded here so the next session does not re-propose it without the prefill cost and
`PromptStanceSyncTests` in view.

### R2. The renderer strips its own scaffolding (`REQ-REF-009`)

`ReplyRenderer` is the single choke point for Ask bodies (050 R4) and must remove
bracketed prompt furniture before a body ships: the evidence legend and its `none` /
`ambient` notes, `[Today: …]`, `[Computed]`, and any residual brace.

The pass runs **after** markers have become placeholders — so a bracket pattern cannot
eat an expansion — and after reference-marker stripping, but **before** quote-shaped
span resolution (or `[Evidence: none — …]` is quotation-shaped and takes a neighbouring
sentence with it) and **before** the unbacked-date ban (or `[Today: …]` yields
`[Today: ]` and a false `strippedDateCount`). Patterns are built through the existing
`RenderText.regex` helper so a bad pattern degrades to a no-op rather than throwing —
the `spans()` lesson from 046 R1.

A `strippedScaffoldCount` counter joins `ReplyRenderStats` and the eval row.
`ReplyRenderer.version` becomes `reply-render@2`.

**Acceptance:**
- Given a body containing any scaffolding literal, when rendered, then the literal is
  absent and the counter incremented.
- Given a body whose only date is inside `[Today: …]`, then `strippedDateCount` is not
  incremented.
- Given a warehoused run, then `leak.*` returns to zero on both arms.

### R3. Asserted dates are scored (`REQ-EVD-007`)

A new `hall.unbackedDate` fires when a reply asserts a month-and-day that matches no
cited entry's date. `AskCitation` already carries `entryDate`, so no new plumbing is
required; the scorer takes citations the way `uncitedQuote` does.

**Report-only on arrival** (046 R1's rule): measure first, threshold after two
warehoused runs. It ships with a firing fixture and a registry entry, or it does not
ship — a scorer that cannot fire reads as a pass, which is how this series began.

**Acceptance:**
- Given a reply asserting a date no citation supports, then exactly `hall.unbackedDate`
  is emitted.
- Given a reply whose dates all match cited entries, then nothing is emitted.
- Given the coverage test, then the new code appears in the covered set.
- Given `gating()`, then the code does not gate.

### R4. Confidence crosses the retrieval boundary, and `k` may narrow (`REQ-RET-001`)

`RetrievalResult` carries a confidence signal — the top score and its margin over the
runner-up, both already computed inside `retrieve` and currently discarded. With it,
`sliceRetrieval` may narrow the prompt cap below 5 when one entry decisively wins, and
holds at 5 otherwise.

Thresholds are calibrated against the gold set offline, never guessed. The narrowing
ships **behind a flag, report-only**, until the pointing number justifies a default
change: `k` is product-visible, and 7 of the 45 gold questions have multi-entry answers.

**Acceptance:**
- Given a decisive top match, when the cap narrows, then recall@5 on both gold sets is
  unchanged for those questions.
- Given a short warehoused run with narrowing enabled, then the pointing rate on
  matched turns exceeds 15.6% and the citation rate stays at or above 35%.
- Given the flag off, then behaviour is bit-identical to today.

### R5. A held-out gold set exists before any tuning (`REQ-RET-002`)

The shipped weights were fitted on the 45-question gold set and a grid search over the
same set is one environment variable away. No retrieval change may be justified by a
number measured only on the set it was fitted to.

Held-out questions are authored in the weak categories — first-mention, within-window,
entity-time — validated by `Fixtures/validate_corpus.py`, and reported as a separate
column from the fitted set in every retrieval report.

**Acceptance:**
- Given a retrieval change, when `RetrievalGate` runs, then it reports fitted and
  held-out recall separately.
- Given a change that improves fitted recall and does not improve held-out recall, then
  it is rejected.

### R6. Temporal retrieval is fixed at the three measured mechanisms (`REQ-RET-003`)

Findings 5, 6 and 7 are distinct and are fixed distinctly:

1. **Earliest-preference for origin questions.** Suppressing recency is not the same as
   preferring the earliest; an explicit ordering is required.
2. **Cue coverage.** Bare `first` before a noun, and life-event verbs, reach
   `seeksOrigin`. The recency-cue override that keeps "when did I last…" out stays.
3. **Within-window significance.** When a date window has already constrained the
   candidate set, the σ bar is redundant; relax it inside a window so in-window entries
   compete on lexical signal.

Passage granularity is explicitly **not** a lever here (finding 10).

**Acceptance:**
- Given the fitted and held-out sets, then recall@5 exceeds 0.760 on both and temporal
  recall exceeds 0.636.
- Given "When did I start pottery classes?", then the earliest supporting entry is in
  the returned set.
- Given "What was I working on last December?", then the returned set stays inside the
  window and contains the supporting entry.

## Out of Scope

- **`periodSummary` / `periodCompare`.** A product capability with its own spec. Framed
  as "year in review", never as hallucination control; any `themeLabel` must be derived
  from evidence the user can open, or omitted.
- **Passage re-chunking, embedding format, ANN, two-stage retrieval.** Finding 10 gives
  the mechanism for why granularity is the wrong lever, and 044 owns the rest.
- **Raising `maxEntries` above 5.** R4 narrows; it never widens.
- **`.nearbyOnly`.** Recorded as finding 9 so it is not rediscovered a fourth time.
- **`TurnClassifier` degeneracy** — `followup` at 76.7%, `correction` at 2. Unchanged
  by this spec and still 047's.
- **Numeric release gates set before measurement.** R3 and R4 land report-only.

## Tasks

- [ ] 0. `spec(051)`: this plan; close out 050's status and the ROADMAP Gate E row with
      Study III's measured outcome, including the two failed predictions.
- [ ] 1. `prompts`: marker grammar conditional on pack state; `noneNote` simplified;
      `ask-core@20` / `ask-degraded@20`; update the four prompt test suites. (R1)
- [ ] 2. `renderer`: `stripScaffolding` pass, `strippedScaffoldCount`,
      `reply-render@2`, `ReplyRendererTests` fixtures. (R2)
- [ ] 3. `eval`: `hall.unbackedDate` with pattern, registry, report-only registration,
      firing fixture, coverage entry, three call sites. (R3)
- [ ] 4. `fixtures`: held-out gold questions; `RetrievalGate` reports both sets. (R5)
- [ ] 5. `retrieval`: earliest-preference, cue coverage, within-window significance;
      re-measure after each. (R6)
- [ ] 6. `retrieval`: confidence on `RetrievalResult`; flagged narrowing in
      `sliceRetrieval`; offline calibration. (R4)
- [ ] 7. Study IV: pre-register, run both arms at 100, archive, write up.
- [ ] 8. Register in `specs/README.md` and `ROADMAP.md`.

## Verification

- [ ] `PromptStanceSyncTests`, `AskPromptContractTests`, `PromptRegistryResolutionTests`,
      `AskPromptSizeTests` green; a `none`-pack prompt contains no `{{`.
- [ ] `ReplyRendererTests` green with a scaffolding fixture per literal.
- [ ] `ChatEvalScoringTests` green — `hall.unbackedDate` fires, is covered, does not gate.
- [ ] `TEST_RUNNER_RETRIEVAL_GATE=1` reports fitted and held-out recall, both above 0.760.
- [ ] `scripts/ci/check_single_intelligence_importer.sh` still reports exactly 1.
- [ ] Study IV: `dropped_markers` → ~0, `leak.*` → 0, `hall.unbackedDate` measured,
      pointing rate reported against 15.6%.
- [ ] The default merge lane is unaffected: without its opt-in flag the long-form suite
      still skips.

## Regression Guards

- **Spec 050's invariant** — pack-backed or unsaid. R1 removes a grammar, never a check.
- **046 R1 / 048 R1** — every scorer ships with a firing fixture. R3 obeys it.
- **`technology/04-evaluations.md`** — measure first, threshold after. R3 and R4 land
  report-only; R5 exists so "measured" cannot mean "measured on the training set".
- **`REQ-INT-001`** — exactly one module imports `FoundationModels`. Untouched.
- **CONSTITUTION §4 rule 3** — content-free logs. Counters only; no spans, no entry text.
- **037 R7** — five entries is the UX ceiling. R4 narrows below it and never above.
