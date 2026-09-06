---
id: 045
title: Computed Insights and Period Reflection
tier: P2
status: draft (2026-09-06)
effort: 5–7 sessions; each phase ships independently
depends_on: [014, 017, 018, 019, 022, 026, 037, 038, 041, 044]
findings:
  - weekly-store-never-written-by-generation
  - patterns-tab-is-one-bar-chart
  - stored-reflection-schema-unwritten
  - entry-has-no-valence-moods-topics-salience
  - starter-tiles-ask-questions-the-pipeline-cannot-answer
  - model-forbidden-to-count-so-counts-must-be-swift
source_refs: [REQ-INT-001, REQ-INT-013, REQ-SUR-001, REQ-SUR-002, REQ-SUR-003, REQ-SUR-005, REQ-PRM-001, REQ-PRM-004, REQ-PRIV-001, REQ-PRIV-002, REQ-VOX-006]
tech_refs: [technology/01-foundation-models.md, technology/04-evaluations.md, technology/07-app-intents-and-surfaces.md]
---

# 045 — Computed Insights and Period Reflection

**Traceability:** implements the **write-time tagger** and **read-time
arithmetic** that spec [`019`](019-surfaces.md) R2/R3/R4/R5 already
specified and that [`017`](017-intelligence-boundary-and-prompt-architecture.md)
R5 contracted as `EntryReflection` / `PeriodReflection`. Ask generation
work stays [`044`](044-agentic-harness-depth.md) / [`039`](039-reply-channels-and-phatic-generation.md);
this spec consumes 044 R1's passage vectors and never re-owns retrieval.
Safety is [`026`](026-behavioral-safety-guardrails.md). Speakable weekly
prose is [`018`](018-capture-and-voice-output.md) `REQ-VOX-006`. Counts
never leave Swift ([`037`](037-conversational-recall-experience.md) rule 3).

**Does not implement:** `BGProcessingTask` Sunday scheduling (019 R8) —
foreground fallback on Journal open is the first ship; the scheduler is a
follow-on once the generate path is proven. Monthly `.deep` / PCC narration
lands with the iOS 27 SDK the way 044 R4 does. `SpotlightSearchTool` is
not used (016 Branch B / DEC-002).

## Why

Ask can retrieve five excerpts and talk about them. It cannot honestly
answer "how has my mood shifted" or "how many times did I write about my
brother" because 037 forbids the model from counting and the journal is
still a pile of prose. Weekly reflection is a `UserDefaults` key that
only `LegacyStoreImporter` writes. Patterns is one bar chart. The
`StoredReflection` / `moodLabels` schema (015) is unwritten.

The product rule is the same as 044: **code decides, the model narrates.**
Swift computes facts with an `n`. AFM, when it runs, is handed those facts
and a salience-ranked slice of entries and is forbidden to invent numbers.

## Technology References

- `technology/01-foundation-models.md` §4 — `@Generable` enums are the
  point; 017 R5's `EntryReflection` / `PeriodReflection` are adopted
  verbatim.
- `technology/04-evaluations.md` — `RestraintGate` thresholds (022 R2).
- `technology/07-app-intents-and-surfaces.md` — `ReadWeeklyReflectionIntent`
  already exists; this spec gives it a generated body.

## Current State (evidence)

Line numbers accurate on 2026-09-06; re-verify before coding.

| # | Finding | Evidence |
|---|---------|----------|
| 1 | `WeeklyReflectionStore.save` is never called by generation; only `LegacyStoreImporter` writes | `WeeklyReflectionStore.swift:23-27`; `rg` of `.save(` |
| 2 | `PatternsView` is entry-count + one 5-bucket chart; copy admits the model never sees numbers | `WeeklyReflectionView.swift:45-76` |
| 3 | `StoredReflection`, `moodLabels`, `HealthSnapshot` exist; nothing writes tags or reflections at save | `JournalSchema.swift:70-77`, `:102-121`; `Entry.swift` has no valence/moods/topics |
| 4 | 017 R5 contracts `EntryReflection` / `PeriodReflection` verbatim; `GenerationIntent` has only `ask`, `summary`, `profileEstimate` | `017-intelligence-boundary-and-prompt-architecture.md:295-319`; `IntelligenceService.swift:21-25` |
| 5 | Empty-state starters invite mood-shift and "actionable plan" answers the pipeline cannot / must not give | `ThemeAwareChatStarters.swift:31-57`; 019 R6 / 044 R3 |
| 6 | `ReadWeeklyReflectionIntent` reads `WeeklyReflectionStore.latestBody` | `MementoAppIntents.swift:33-45` |

## Requirements

### R1. `InsightFact` and `InsightEngine` — arithmetic, no model

A FoundationModels-free module `Services/Intelligence/Insights/`:

```swift
struct InsightFact: Sendable, Equatable {
    enum Kind: String, Sendable { case count, cadence, cluster, person, place, valenceTrend, lastMention }
    var kind: Kind
    var label: String
    var value: String          // display, already formatted
    var n: Int                 // mandatory; drives low-confidence
    var window: DateInterval
    var supportingEntryIDs: [UUID]
}
```

Computes, against the local corpus and 044 R1 passage vectors when present
(whole-entry vectors until 044 Phase 1 lands):

- **Cadence** — entries this week / month, streak, longest gap, hour-of-day
  histogram.
- **Clusters** — agglomerative groups over cached embeddings; label by top
  IDF terms from `EntryRetriever`'s keyword scorer.
- **People / places** — `NLTagger` `.nameType`; frequency, first/last
  mention.
- **Valence trend** — only after R3 has tagged entries; otherwise omitted.

Every charted or spoken correlation shows `n`. Below a documented
threshold (`n < 4` draft, fit against fixtures) the fact is
`.lowConfidence` and UI greys it or suppresses it (`REQ-SUR-001`). The
model never receives a suppressed fact.

**Acceptance:** `InsightEngineTests` over `Fixtures/corpus` produce golden
cadence counts (including the two sparse weeks 2025-12-22 and 2026-05-04
as low-confidence). No `import FoundationModels` in the Insights folder
(`check_single_intelligence_importer.sh` still reports 1).

### R2. Patterns tab consumes facts, not prose

`PatternsView` renders Swift Charts from `InsightFact`s: cadence bars
(already sketched), cluster keyword chips, people/places list. Adopt or
delete `KeywordsCard` / `SentimentAnalysisCard` in the same change (019 R4
reuse ledger). Charts render while any narration is generating, degraded,
or `hasNothingToSay`. Low-confidence facts use the draft copy *"Based on N
entries — too few to call a pattern."*

**Acceptance:** UI test on the fixture corpus: every visible correlation
shows `n`; a constructed `n < 4` fact shows the low-confidence state;
opening the tab never blocks on generation.

### R3. Entry reflection at save — 017's `EntryReflection`, Z0

Add `GenerationIntent.entryReflection` (Z0, `degradedZone: nil`,
`.interactive`). Prompt `entry-reflect@1`. `@Generable struct
EntryReflection` adopted **verbatim** from 017 R5. Closed `MoodLabel` /
`TopicLabel` enums; vocabulary version stamped on the persisted
reflection.

Trigger from `EntryViewModel.createEntry` / `updateEntry` as a detached
`.utility` task **after** the save commits. The entry text is
byte-identical whether or not the reflection succeeds (019 R2). Safety
(`SafetyRouter.decide` on the entry text) runs first; crisis shows the
static card on the entry surface and still saves the entry.

Persist: `StoredEntry.moodLabels`, a `StoredReflection(kind: .entry)` with
`zoneRaw`, `promptVersion` via the existing relationship. Backfill existing
entries on the same warm queue as `EntryRetriever.warmEmbeddings`, one at
a time, with `RefusalOutageTracker` semantics — a broken model asset stops
the queue. A guardrail refusal is the **quiet** state (no observation
line, no error) per 017 R4 / 019 R2.

**Acceptance:**
- Given an ordinary fixture entry saved, when reflection completes, then
  summary/moods/topics persist and `salience < threshold` produces no
  observation line.
- Given a generation failure, when the entry is reopened, then retry is
  silent and the transcript is unchanged.
- `ModelRouterTests` / `PromptRegistryResolutionTests` green with the new
  intent.

### R4. Weekly `PeriodReflection` — foreground first

Add `GenerationIntent.weeklyReflection` (table default Z1 `.moderate`,
degraded Z0; today resolves `.sdkUnsupported` → Z0 baseline, `wasDegraded:
false`, same honesty as Ask). Prompt `weekly@1` / `weekly-degraded@1`.
`@Generable struct PeriodReflection` adopted **verbatim** from 017 R5.

Input is **computed facts + salience-ranked entries**, not the raw week:
`InsightEngine` facts for the week (counts stay in card chrome; the prompt
receives labels and `n` only as "several" / "a few" / "one" — never
digits) and the salience-ranked slice bounded by `ContextBudget`.
`groundedEntryIDs` reconcile against IDs actually in context (same
anti-fabrication as `reconcileCitations`). `hasNothingToSay` renders the
quiet card (*"A quiet week. Not every week has something worth saying."*)
and still marks the week covered.

**Trigger (v1):** on Journal appear, if the previous ISO week is uncovered
and has ≥ 1 entry, generate in the foreground with a "writing now…" card.
No `BGProcessingTask` in this spec (019 R8 remains open). Persist via
`WeeklyReflectionStore.save` + `MementoDataStore.upsertWeeklyReflection`.
Thumbs write `StoredReflection.ratingRaw` (041 analogue). Body passes
`SpeakabilityLinter` (`REQ-VOX-006`). `ReadWeeklyReflectionIntent` keeps
its current read path. Optional read-aloud via `VoicePlaybackService`.

**Acceptance:**
- Given a generated week, when the card renders, then every citation
  tap-through lands on the cited entry.
- Given a seeded sparse week, when generation runs, then `hasNothingToSay`
  is true, no prose/audio exists, and the week reads as covered.
- Given airplane mode and a ready reflection, when play is tapped, then
  audio starts (018 criterion, exercised here).

### R5. Computed answers in Ask — 019 R5 without Spotlight

`TurnClassifier` gains a high-precision **quantitative** path
(`how many` / `how often` / `when did I last` / `how has X changed`) that
does not steal genuine journal asks. `ReplyChannel` maps it to a new
`.statistic` case: retrieval off, 64-token companion-temperature
narration **optional**. `InsightEngine` runs first; the result is a
first-class section on `ChatStreamEvent.delta` (like
`reviewedCitations` today) rendered in `AIOutputComponent` before or
without body text.

`InsightEngine` facts may also be attached as a `[Computed]` block on
notebook turns that already retrieved (044 Phase 3+). The stance line
says narrate the block; `AskAnswer` schema is unchanged. A fact the
chart suppressed is never in the block (`insight.contradictsSuppressed`
is a new `ChatEvalScoring` family).

Re-author `ThemeAwareChatStarters` fallbacks to questions the engine can
answer; 044 R3 owns the advice-starter deletion and the lint hook — this
spec owns the quantitative templates.

**Acceptance:**
- Given "How many times did I write about my brother this year?" against
  the fixture corpus, when Ask runs, then the UI shows the Swift count
  with tap-through IDs and the model body does not contain a digit that
  disagrees with `n`.
- Given `n < 4`, when the turn completes, then the low-confidence copy
  shows and no pattern is claimed.

### R6. Eval

- `InsightEngine` goldens: deterministic, SDK-free, merge-lane.
- `RestraintGate` (022): report-only for two runs, then
  `hasNothingToSay` ≥ 90% on the seeded sparse weeks; observation
  suppressed ≥ 60% of ordinary fixture entries (needs R3).
- `insight.*` violations in `ChatEvalScoring` (gated): prose states a
  number a suppressed fact forbade, or contradicts a `[Computed]` block.
- Weekly generations warehouse as `harness_gate` (or a dedicated kind if
  043 is extended) with `prompt_version` / `model_identifier` per 043 R2.

## Phasing

| Phase | Ships | Needs |
|---|---|---|
| **A — Facts** | R1 engine + R2 Patterns + R5 classifier/UI (cadence/people/places; no valence yet) | Current embeddings; 044 R1 improves clusters when it lands |
| **B — Tags** | R3 entry reflection + backfill | 017 router/registry exhaustiveness |
| **C — Weekly** | R4 foreground weekly card + intent + speakability | R1 + ideally R3 salience |
| **D — Close the loop** | `[Computed]` on notebook turns; valence trends; `insight.*` gate armed | 044 Phase 2 (`ask-core@16`) so prompt tokens have room |

## Out of Scope

- 044 passage index, tool loop, lean prompt, living profile.
- `BGProcessingTask`, weekly-ready notification scheduling (019 R8).
- Monthly `.deep` narration / PCC.
- HealthKit raw samples (DEC-006: coarse Z0 snapshots only; never in Z1).
- Therapeutic framing, scores-as-grades, streaks-as-engagement (038
  non-goals / REQ-POS-001).

## Tasks

- [ ] 1. `InsightFact` + `InsightEngine` (cadence, clusters, NLTagger
      people/places) + goldens over `Fixtures/corpus` (R1)
- [ ] 2. `PatternsView` + adopt-or-delete Insights-Data cards; low-confidence
      copy (R2)
- [ ] 3. `TurnType.quantitative` + `ReplyChannel.statistic` +
      `ChatStreamEvent` fact payload + `AIOutputComponent` stat section (R5)
- [ ] 4. Archivist quantitative starters; 044 R3 advice-starter already
      gone (R5)
- [ ] 5. `GenerationIntent.entryReflection` + router row +
      `entry-reflect@1` + `@Generable EntryReflection` + persist + backfill
      + quiet refusal (R3)
- [ ] 6. `GenerationIntent.weeklyReflection` + router row + `weekly@1` +
      `@Generable PeriodReflection` + foreground trigger + card + rating +
      speakability (R4)
- [ ] 7. `[Computed]` block on notebook turns; `insight.*` scoring family (R5, R6)
- [ ] 8. Register in README and ROADMAP; amend 019 R4/R5 to cite this spec
      as the Branch B implementation (not Spotlight)

## Verification

- [ ] `InsightEngineTests` match golden counts on the fixture corpus
- [ ] Sparse weeks produce `.lowConfidence` / `hasNothingToSay` as specified
- [ ] Patterns tab shows `n` on every correlation; `n < 4` is greyed
- [ ] Quantitative Ask turn renders a number that matches `InsightEngine`
      and does not disagree in the body
- [ ] Entry save with reflection failure leaves transcript byte-identical
- [ ] `SpeakabilityLinter` clean on weekly bodies
- [ ] `ModelRouterTests` / `PromptRegistryResolutionTests` /
      `check_single_intelligence_importer.sh` green
- [ ] `lint_forbidden_phrases.py` clean on new UI copy and starters

## Regression Guards

- **REQ-INT-001** — `@Generable` types and session construction live in the
  single importer. `InsightEngine` is FoundationModels-free.
- **037 rule 3** — the model never emits a count. Facts carry `n` in Swift;
  prompts say "several" / "a few"; `insight.*` fails a digit that
  contradicts or invents.
- **026** — safety on entry text before reflection; safety on weekly user
  blob before period generation; crisis card is additive, never a content
  gate on the entry itself (019 R7).
- **014 R2** — every generation surface (entry reflection, weekly)
  persists zone / `wasDegraded` / `promptVersion` / `modelIdentifier` and
  discloses degradation at the point of use.
- **REQ-SUR-001** — no correlation without `n`; suppressed facts never
  enter a prompt.
- **REQ-VOX-006** — weekly `body` / `observation` are speakable.
- **CONSTITUTION §4.2** — `StoredEntry` / `StoredReflection` already have
  the columns; do not add shipped `@Model` properties without a
  `SchemaMigrationPlan`. New fields go on `ExperienceProfile` JSON or
  existing optional columns.
- **038 non-goals** — no therapeutic framing, no scores-as-grades.
