---
id: 044
title: Agentic Harness Depth — Retrieval, Tools, Living Profile, Lean Prompt
tier: P2
status: draft (2026-09-06)
effort: 6–8 sessions across four phases; each phase ships independently
depends_on: [017, 022, 037, 039, 041, 043]
findings:
  - whole-entry-embedding-dilutes-recall
  - excerpt-is-first-500-chars-not-best-passage
  - retriever-weights-never-fit-to-gold
  - nomatch-stance-contradicts-ambient-evidence
  - no-tool-loop-so-no-multi-hop
  - onboarding-themes-stored-but-inert-in-ask
  - lens-is-one-shot-never-refreshed
  - ask15-restates-per-turn-tags-in-instructions
  - chars-per-token-heuristic-where-tokencount-exists
  - starter-tile-invites-advice
source_refs: [REQ-INT-001, REQ-INT-010, REQ-INT-017, REQ-IDX-007, REQ-PRM-001, REQ-PRM-004, REQ-SUR-002, REQ-SUR-003, REQ-PRIV-001]
tech_refs: [technology/01-foundation-models.md, technology/03-spotlight-retrieval.md, technology/04-evaluations.md]
---

# 044 — Agentic Harness Depth: Retrieval, Tools, Living Profile, Lean Prompt

**Traceability:** deepens the Ask pipeline that spec
[`017`](017-intelligence-boundary-and-prompt-architecture.md) owns (single
importer, `GenerationIntent`, `PromptRegistry`, stateless sessions) without
moving the boundary. Notebook voice and the Meet / Notebook / Sit / Open
recipe remain [`037`](037-conversational-recall-experience.md); the channel
effort curve remains [`039`](039-reply-channels-and-phatic-generation.md);
safety runs first and is [`026`](026-behavioral-safety-guardrails.md). The
L1 lens and `ThemeCatalog` estimate are
[`038`](038-experience-profile-and-theme-estimation.md); this spec gives the
stored profile a job beyond one prompt line. Eval mechanics are
[`022`](022-evaluation-and-quality-study.md) with run identity from
[`043`](043-eval-run-warehouse.md).

**Does not implement:** computed insights, entry tagging at save, weekly /
monthly `PeriodReflection` (a sibling spec, referenced here as **045** where
this spec consumes its outputs); Private Cloud Compute routing (rows exist in
`ModelRouter`; the Z1 leg lands when the app builds against an SDK that has
`PrivateCloudComputeLanguageModel` and the app is approved); Dynamic Profiles
(deferred — see R4's note).

## Why

The harness today is a **deterministic orchestrator around one constrained
generation**: `TurnClassifier` → `ReplyChannel` → `RetrievalPolicy` →
`EntryRetriever` → stance → `buildAskPrompt` → one guided `AskAnswer` stream,
tools off. That design is correct for a ~3B on-device model and is why the
pipeline is testable. It leaves four ceilings the model cannot be prompted
past:

1. **Retrieval is the quality ceiling.** One pooled vector per whole entry
   and a first-500-characters excerpt mean a long day-dump that mentions Maya
   in paragraph four neither matches "who is Maya" nor shows the model the
   paragraph if it does. Under-scoring is what the code itself blames for the
   `.noMatch` contradiction (evidence row 4). The retriever's weights were
   set by hand and never fit against the gold set that already exists.
2. **No agency where it would pay.** Retrieval runs once, before generation,
   on the current message or a four-turn-back anchor. A multi-hop ask
   ("what did I write about the thing Maya mentioned?") is structurally
   unreachable. The plumbing for tools exists and is hard-wired off.
3. **Onboarding is under-used.** The person told the app their name, a
   free-text reflection, and confirmed 3–6 themes. Ask uses the name and an
   80-character lens. Themes are deliberately kept out of the prompt (037's
   "goals are not the subject" — correct) and therefore do nothing at all.
   The lens is estimated once and never learns from the journal.
4. **The prompt pays for what the pipeline already decided.** `ask@15`
   spells out eight per-stance behaviours in the instructions *and* the
   pipeline restates the chosen one as a `[Turn:]` line every turn. Every
   speculative miss re-prefills all of it.

The product rule stays the one 037/039 set: **code decides, the model
renders.** This spec widens what code can decide (better evidence, a bounded
tool loop, priors from the profile) and narrows what the model must read.

## Technology References

- `technology/01-foundation-models.md` §3 — `contextSize` and
  `tokenCount(for:)` (✅ iOS 26.4+, five overloads incl. `Instructions`,
  `[any Tool]`, `Collection<Transcript.Entry>`): budget piecewise, not by
  chars ÷ 4.
- `technology/01-foundation-models.md` §5 — `Tool` protocol; ✅ registration
  is **instances only** (`tools: [SearchJournalTool()]`); ✅
  `GenerationOptions.ToolCallingMode` `.allowed / .required / .disallowed`
  (iOS 27.0+); `SpotlightSearchTool` lives in the `_CoreSpotlight_FoundationModels`
  overlay and is **not** used here (DEC-002 Plan B: Spotlight indexing is
  opt-in off; `EntryRetriever` is the retrieval layer per `REQ-IDX-007`).
- `technology/01-foundation-models.md` §4 — `ContextOptions(includeSchemaInPrompt:)`.
- `technology/01-foundation-models.md` §7 — Dynamic Profiles (deferred; R4 note).
- `technology/04-evaluations.md` — gate posture: measure first, threshold
  after (`AgenticEval` reports, `ChatEvalGate` fails).

## Current State (evidence)

Line numbers accurate on 2026-09-06; re-verify before coding.

| # | Finding | Evidence |
|---|---------|----------|
| 1 | One pooled sentence vector per **whole entry**, text = `"\(title). \(text)"`, English `NLEmbedding` only | `EntryRetriever.swift:366` (`entryVector(id:text:)`), `EmbeddingService.swift:50` (`sentenceEmbedding(for: .english)`), `EmbeddingService.swift:470` (`pooledSentenceVector`) |
| 2 | Context-block excerpt is the **first** `maxContentChars` (500) of the entry, not the matching passage | `EntryRetriever.swift` `RetrievedEntry` construction; `RetrievalLimits.init(budget:)` `EntryRetriever.swift:120-127` |
| 3 | Hybrid weights (semantic 5.0, keyword 1.0, recency 0.5) and `RetrieverTuning` thresholds are hand-set; no offline test fits them to `Fixtures/gold` | `EntryRetriever.swift:146-149`, `EntryRetriever.swift:57-83`; `Fixtures/gold/*.json` carries `expectedEntryIDs` consumed only by live `ChatEvalGate` / `AgenticEval` |
| 4 | `.noMatch` stance ships ambient entry text and tells the model nothing matches; withholding was tried and reverted because ordinary recall is `.noMatch` "only because retrieval under-scores them" | `FoundationModelsIntelligenceService.swift` `buildAskPrompt`, comment block above the `framing` selection (≈ lines 1370–1399) |
| 5 | Tools are plumbed and hard-wired off | `FoundationModelsIntelligenceService.swift:394` (`toolDefinitions: []`), `:721` (`toolsEnabled: false`); `GenerationRequest.toolsEnabled` `IntelligenceService.swift:44` |
| 6 | Follow-up grounding re-runs retrieval on a single anchor text found by walking back ≤ 4 user turns; no second retrieval within a turn | `RetrievalPolicy.swift:136-149` (`followupAnchor`), `FoundationModelsIntelligenceService.swift:650-660` |
| 7 | Onboarding stores name, reflection, `confirmedThemeIds`, `promptLens`; Ask injects only name + ≤ 80-char lens on companion/notebook/thread | `ExperienceProfile.swift:11-27`, `PromptRegistry.swift:98-105` (`hasAskPersonalization`), `:188` (`maxAskPromptLensChars = 80`), `:544-563` (`personalizationSection`) |
| 8 | `confirmedThemeIds` reach chat only as starter-tile labels; never as a retrieval prior | `ThemeAwareChatStarters.swift`; no reference to `confirmedThemeIds`/`ThemeCatalog` in `EntryRetriever.swift` or `RetrievalPolicy.swift` |
| 9 | Lens is estimated once from onboarding text (`estimateProfile`) and never refreshed from the journal | `FoundationModelsIntelligenceService.swift:1122-1189`; `ExperienceProfile.builtAt` written only by onboarding / `LocalProfileStore` setters |
| 10 | `ask@15` instructions enumerate all eight stances; the pipeline also emits the chosen stance as the first prompt line every turn | `PromptRegistry.swift:306-462` (instructions), `:397-427` (per-tag list); `RetrievalPolicy.swift:41-77` (`TurnStance.promptLine`) |
| 11 | `ContextBudget` derives caps from `contextSize × share × 4 chars/token`; `tokenCount(for:)` is available from iOS 26.4 and unused | `ContextBudget.swift:76` (`charsPerToken = 4.0`); `technology/01-foundation-models.md:75` |
| 12 | Empty-state starter "Create an actionable plan based on my recent habits and daily patterns" invites advice the persona refuses (`REQ-SUR-002`) | `ThemeAwareChatStarters.swift:31-35`, `:48-52`; `specs/019-surfaces.md` R6 |
| 13 | Per-generation perf line logs latency, window, and entry count but not prompt tokens or tool-call count | `FoundationModelsIntelligenceService.swift:522-542` (`logOutcome`) |

## Requirements

### R1. Passage-level retrieval — the best paragraph, not the first 500 characters

Entries are chunked into passages of 2–4 sentences (`NLTokenizer(unit:
.sentence)`, merged to a 120–400 character target, never splitting inside a
sentence). Each passage is embedded and cached in the existing `MEV1`
record format keyed by `(entryID, passageIndex, contentHash)`; the
whole-entry vector is retained as a fallback for corpora that have not
finished re-indexing. Warm-up reuses `EntryRetriever.warmEmbeddings`'s
low-priority pass; re-chunking happens only when `contentHash` changes.

Scoring becomes **max-passage cosine + 0.15 × mean-passage cosine** per
entry (max finds the paragraph; the mean term breaks ties toward entries
that are about the topic rather than mentioning it once). Keyword, recency,
and date-window logic are unchanged. `RetrievedEntry.text` becomes the
**best-scoring passage** with one neighbouring sentence of context on each
side, capped at `maxContentChars`; `quotedSpan` is extracted from that
passage. The context-block header and `[ref N | date]` shape do not change.

Non-English entries: run `NLLanguageRecognizer` once per entry at index
time; when the dominant language has no sentence embedding, fall back to
`wordEmbedding` for that language, then to keyword-only scoring. An entry
must never score zero *because* of its language.

**Acceptance:**
- Given the fixture corpus, when `RetrievalGate` (R2) runs before and after
  this change, then recall@5 over gold rises and no gold item regresses from
  hit to miss.
- Given a 900-word fixture entry whose gold passage is beyond character 500,
  when retrieved, then the context block shows that passage and
  `hall.uncitedQuote` does not fire on a reply that quotes it.
- Given an entry edit, when re-indexed, then only passages whose text
  changed are re-embedded (unit test on cache keys).

### R2. `RetrievalGate` — retrieval is measured offline, and the weights are fit, not guessed

A deterministic XCTest (`TEST_RUNNER_RETRIEVAL_GATE=1`, no model, runs in
`ios-build-online.yml`) loads `Fixtures/corpus` + `Fixtures/gold`, runs
`EntryRetriever.retrieve` for every gold question, and reports **recall@5,
precision@5, MRR, abstention accuracy** (gold `match: "none"` must return
`.empty` or ambient, never a strong hit). It also emits per-item CSV to
`.eval-runs/retrieval/`, importable through 043's `import_run.sh` with
`kind = retrieval_gate`.

A companion script (`scripts/eval/fit_retriever.swift` or a test with
`RETRIEVER_GRID=1`) grid-searches `RetrieverTuning` and the three hybrid
weights against the same gold and prints the top configurations. **The
winning configuration is committed with the grid output in the PR** — the
weights become a claim with evidence, per 043's posture.

Threshold posture follows 022: report-only for the first two measured runs;
then `recall@5 ≥ 0.85` and `abstention accuracy ≥ 0.90` gate, matching 022
`RetrievalGate`'s stated bar.

**Acceptance:**
- Given `xcodebuild test -only-testing:MeetMementoTests/RetrievalGate`, when
  run on a Mac with no Apple Intelligence, then it completes and writes the
  report (the gate is SDK-free).
- Given a planted change that zeroes the semantic weight, when the gate runs
  after thresholds are armed, then it fails.

### R3. Profile priors — the onboarding profile steers retrieval and starters, never the prompt

`confirmedThemeIds` stay out of instructions (037: goals are not the
subject). They become **retrieval priors** instead:

- On `.share` and `.reflectiveQuestion` turns (companion channel, retrieval
  off today), retrieval stays off. No change — the rule that sharing does not
  pull the notebook is 037's and stands.
- On `.journalQuery` turns, an entry whose passage matches a confirmed
  theme's `synonyms` (from `ThemeCatalog`) receives a bounded boost
  (`themeBoost`, default 0.5, fit in R2's grid alongside the other weights).
  Themes cannot create a signal on their own — `hasSignal` is unchanged —
  they reorder entries that already cleared the bar.
- `ThemeAwareChatStarters` draws its prompts from an archivist-compatible
  template set keyed by theme *family* and audited with the 014 R3
  forbidden-phrase lint; the "actionable plan" starter (evidence 12) is
  removed. Starters are only offered when the corpus can plausibly answer
  them (≥ 3 entries in the theme's cluster, computed via R1's passage
  vectors) so the empty state never invites a question the notebook cannot
  meet.
- The stored **reflection** text remains unused in Ask. It is the input to
  R6's refresh only.

**Acceptance:**
- Given a profile with `relationships` confirmed and a corpus where two
  entries tie on score, when retrieved for a journal question, then the
  relationships-matching entry ranks first; given the same corpus with no
  confirmed themes, then the order is unchanged from today (unit test).
- Given every starter template, when run through
  `scripts/ci/lint_forbidden_phrases.py`, then zero hits.

### R4. Bounded tool loop — `SearchJournalTool` on notebook and thread turns only (iOS 27 SDK)

The single importer gains a `SearchJournalTool: Tool` wrapping
`EntryRetriever.retrieve` with the same `RetrievalLimits` the pre-retrieval
path uses. It is **not** `SpotlightSearchTool` (DEC-002 Plan B).

```swift
@Generable struct Arguments {
    @Guide(description: "What to look for in the journal, in plain words. Names, places, and topics work best.")
    let query: String
    @Guide(description: "Optional time span in the person's words, e.g. 'last March' or 'this week'. Empty when not stated.")
    let when: String?
}
```

Rules, all enforced in Swift rather than asked of the model:

- **Channel gate:** the tool is attached only when `channel.allowsRetrieval`
  (`notebook`, `thread`). Phatic, continuer, companion, meta, redirect never
  see a tool (039's effort curve, `REQ-INT-017`).
- **Pre-retrieval still runs.** The deterministic pass remains the first
  evidence block; the tool exists for the *second* hop the pass cannot make.
  `toolCallingMode` is `.allowed`, never `.required`.
- **Hard cap: 2 calls per turn.** The tool instance carries a counter; the
  third call returns an authored "no further search this turn" output. Each
  result set is ingested into `SessionCandidatePool` and re-numbered so
  `[ref N]` addressing and `reconcileCitations` remain the single source of
  citation truth — a tool result the reply does not quote or cite is not a
  citation.
- **Safety:** tool `query` text passes `SafetyRouter.decide` before
  retrieval runs; a crisis/hard-refuse classification aborts the turn with
  the same designed error the pre-retrieval path raises.
- **Watchdog and budget:** tool round-trips count toward the 30-second
  generation watchdog; tool output is capped at `RetrievalLimits.maxEntries`
  entries × `maxContentChars`.
- **Provenance:** `GenerationRequest.toolsEnabled` becomes true on these
  turns; the perf log line (R7) records `tools=N`.
- **SDK gate:** compiled under `#if compiler(>=6.3)` and `@available(iOS
  27.0, *)` exactly as image attachments are today. On the iOS 26 SDK the
  turn runs the current tool-free path. Both paths yield the same
  `AskResult` shape; nothing above the boundary knows which ran.

Dynamic Profiles are **not** adopted: 017 R9's stateless-session decision
stands because speculative prewarming already pays the prefill it would
save, and a profile-carrying session cannot be fingerprinted and adopted
the way `AskTranscriptPlan` is. Revisit only if R7's token log shows
instruction prefill dominating after R5.

**Acceptance:**
- Given `AgenticEval`'s multi-hop probes (new: "what did I write about the
  thing Maya mentioned?", "when did I first mention the place I went last
  weekend?"), when run with the tool enabled vs. disabled, then the enabled
  run's `retrievalOutcome == correct` rate is higher and `gen.hitTokenCap`
  is not higher (report-only first two runs, then gated).
- Given a phatic fixture turn, when generated with tools compiled in, then
  the session transcript contains zero tool definitions (unit test on the
  built `Transcript`).
- Given a scripted model that requests three searches, when the turn runs,
  then exactly two `EntryRetriever.retrieve` calls occur.

### R5. Lean instructions — `ask-core@16` plus one channel suffix; stance lives only in the turn line

`ask@15` is split into:

- `ask-core@16` — voice, second-person rule, Meet / Notebook / Sit / Open
  as a *recipe*, the markdown grammar, hard bans, and safety bans. Target
  ≤ 55% of `ask@15`'s token count measured with `tokenCount(for:
  Instructions)` where available.
- One short channel suffix selected by `ReplyChannel`: `notebook`
  (evidence and quoting rules), `thread` (continue, don't restart),
  `companion` (no notebook unless asked), `meta` (capability list),
  `redirect` (outside scope). Each ≤ 6 lines.
- The **per-stance behaviour list is deleted from the instructions.** The
  `[Turn:]` line already carries it, and `PromptStanceSyncTests` is
  re-pointed to assert the *suffix* mentions every `TurnStance.tagPrefix`
  the channel can produce, so the drift guard survives the move.

Two measured experiments ride on the same eval runs and each has a
kill-switch in `PromptRegistry`:

- **Exemplar turn (few-shot via transcript):** on a notebook turn with empty
  history, `AskTranscriptPlan` prepends one synthetic user/assistant pair
  demonstrating Meet → `###` date → italic quote → Sit → one question, built
  from a fixture entry and marked so it never enters `LocalChatStore`. It is
  part of the fingerprinted plan and therefore speculatively prewarmable.
  Keep only if `rule.*` violations fall in `ChatEvalGate` without raising
  `hall.*`.
- **`includeSchemaInPrompt: false`:** the `@Guide` text already restates the
  instructions; measure prefill tokens and `leak.schemaField` with the
  schema omitted. Keep only if leaks do not rise.

Version strings bump per `REQ-PRM-001`; `ask-degraded@16` and the light
prompts are retuned to the same shape.

**Acceptance:**
- Given `ChatEvalGate` at 100% on `ask@15`, when re-run on `ask-core@16` +
  suffixes, then it is still 100% and mean `prompt_tokens` per notebook
  turn (R7) is ≤ 55% of the baseline run, both runs warehoused with
  distinct `prompt_version`.
- Given the exemplar turn enabled, when `LocalChatStore` is inspected after
  a conversation, then no exemplar text is persisted.

### R6. Living profile — the lens learns from the journal, with the person's consent and edit

A new `GenerationIntent.profileRefresh` (Z0, no degraded leg, `priority:
.scheduled`) re-estimates `promptLens` from **computed inputs, not
onboarding prose**: the top passage clusters from R1's vectors (labelled by
IDF terms, as `EntryRetriever` already scores them), confirmed theme
families, and — once 045 lands — tagged topics. The onboarding reflection
is one input among these, weighted no higher than the clusters. Output is
the existing `ProfileEstimateAnswer` shape; validation through
`ThemeCatalog.validate` and the 120-character lens cap are unchanged.

Rules:

- Runs at most once per 14 days and only after ≥ 10 new entries since the
  last `builtAt`; triggered on Journal open at `.utility` priority, never
  during a chat turn.
- The refreshed lens is **proposed, not applied**: it lands in
  `ExperienceProfile.suggestedThemeIds` / a new `proposedPromptLens` with
  `modelIdentifier` and `promptVersion` (`REQ-PRM-004`), and Settings →
  Profile shows "Memento's current read on you" with the current lens, the
  proposal, and Accept / Edit / Keep mine. Nothing changes in Ask until the
  person accepts.
- The lens text is scanned by `OutputSafetyScanner` and the forbidden-phrase
  list; a hit discards the proposal silently.
- `processOnDeviceOnly` and `aiEnabled` are honoured exactly as today; the
  intent is a `ModelRouter` row like any other, so the exhaustiveness tests
  force the entry.

**Acceptance:**
- Given a profile refreshed and not accepted, when an Ask turn runs, then
  `PromptPersonalization.fromLocalProfile().promptLens` is the *old* lens
  (unit test).
- Given a corpus whose clusters are dominated by "running" and "Nonna", when
  refreshed, then the proposal names neither a diagnosis nor an emotion and
  passes `PersonaGate`'s no-advice check.
- Given `GenerationIntent.allCases`, when `ModelRouterTests` runs, then the
  new intent has exactly one row.

### R7. Budget in tokens, log in tokens

Where `tokenCount(for:)` is available (iOS 26.4+ runtime, iOS 27 SDK),
`ContextBudget` is constructed from measured token counts of the resolved
instructions, the transcript tail, and each candidate evidence block, and
`charsPerToken` is used only as the fallback it already claims to be. The
per-generation perf line gains `prompt_tokens`, `cached_tokens`
(`Usage.Input.cachedTokenCount`, the speculative-hit proof), and `tools=N`.
Content-free by construction, as today.

**Acceptance:** given a speculative hit vs. miss on the same turn, when the
perf log is read, then `cached_tokens` is materially higher on the hit —
the first direct measurement of what 029 Amendment A buys.

## Phasing — what ships when

| Phase | Ships | Needs | Why first |
|---|---|---|---|
| **1 — Evidence** | R1 passage index, R2 `RetrievalGate` + fitted weights, R3 theme priors and starter audit | iOS 26 SDK; no model in CI | Largest recall gain, zero generation risk, works on DEC-001 devices; fixes the `.noMatch` root cause the code already names |
| **2 — Prompt** | R5 `ask-core@16` + suffixes; exemplar and schema experiments (kept or killed by the numbers) | Phase 1 (so gains are attributable), 043 warehouse | Cuts prefill on every speculative miss; makes room for tool output and few-shot |
| **3 — Agency** | R4 `SearchJournalTool`, R7 token budgeting and logging | Xcode 27 / iOS 27 SDK | Multi-hop recall; honest token accounting; the `compiler(>=6.3)` pattern already exists |
| **4 — Profile** | R6 living profile with consent UI | R1 clusters; ideally 045 tagging | Highest UX sensitivity; needs the transparency surface before the model touches the lens |

Every phase leaves the app shippable and every phase is a separate eval run
under 043 with its own `prompt_version` / `corpus_id`, so a regression is
attributable to one phase.

## Out of Scope

- Computed insights, entry tagging, `PeriodReflection`, weekly/monthly
  surfaces, `BGProcessingTask` — sibling spec 045.
- Private Cloud Compute routing and `.moderate` / `.deep` reasoning — lands
  with the SDK; `ModelRouter` rows already exist.
- Dynamic Profiles (R4 note), `SpotlightSearchTool` (DEC-002), cross-device
  embedding sync (vectors are a derived cache and rebuild locally).
- Any change to safety ordering, the crisis card, or `PersonaGate`
  thresholds (026 / 019 R7).
- Remote prompt manifest (DEC-003: bundled only).

## Tasks

- [ ] 1. `PassageChunker` (NLTokenizer, merge to 120–400 chars) + `MEV1`
      passage cache keyed `(entryID, passageIndex, contentHash)`; language
      detection + word-embedding fallback (R1)
- [ ] 2. `EntryRetriever`: max+mean passage scoring, best-passage excerpt
      with neighbour sentences, `quotedSpan` from the passage (R1)
- [ ] 3. `RetrievalGate` test + `.eval-runs/retrieval/` report +
      `import_run.sh kind=retrieval_gate` (R2)
- [ ] 4. `RetrieverTuning` grid fit; commit winning weights with grid output
      (R2)
- [ ] 5. `themeBoost` in `EntryRetriever` from `ThemeCatalog.synonyms`;
      archivist starter templates keyed by `ThemeFamily`; delete the
      "actionable plan" starter; lint hook (R3)
- [ ] 6. `PromptRegistry`: `ask-core@16` + five channel suffixes;
      `ask-degraded@16`; re-point `PromptStanceSyncTests`;
      `AskPromptContractTests` version pins (R5)
- [ ] 7. Exemplar turn in `AskTranscriptPlan` with persistence guard; schema
      flag; two warehoused A/B runs each; keep/kill recorded in this spec (R5)
- [ ] 8. `SearchJournalTool` under `compiler(>=6.3)`: channel gate, 2-call
      counter, safety on `query`, pool ingestion and re-ref, `toolsEnabled`
      provenance (R4)
- [ ] 9. `AgenticEval` multi-hop probes and a scripted-tool unit test (R4)
- [ ] 10. `ContextBudget(tokenCounts:)` initialiser; `prompt_tokens`,
      `cached_tokens`, `tools=N` on the perf line (R7)
- [ ] 11. `GenerationIntent.profileRefresh`, router row, `profile-refresh@1`,
      cadence guard, proposal fields on `ExperienceProfile` (R6)
- [ ] 12. Settings → Profile "Memento's current read on you" with Accept /
      Edit / Keep mine (R6)
- [ ] 13. Register in `specs/README.md` and `ROADMAP.md`; mint 045 for
      computed insights

## Verification

- [ ] `RetrievalGate` runs SDK-free on a Mac with no Apple Intelligence and
      writes `.eval-runs/retrieval/report.md`
- [ ] Before/after recall@5 over gold recorded in the PR; no gold item flips
      hit → miss
- [ ] `ChatEvalGate` 100% on `ask-core@16`; `prompt_tokens` ≤ 55% of the
      `ask@15` baseline on notebook turns (two warehoused runs)
- [ ] Phatic turn transcript carries zero tool definitions with tools
      compiled in
- [ ] Scripted third tool call is refused; `EntryRetriever.retrieve` called
      exactly twice
- [ ] `lint_forbidden_phrases.py` clean over starter templates
- [ ] `ModelRouterTests` / `PromptRegistryResolutionTests` green with the
      new intent
- [ ] `check_single_intelligence_importer.sh` still reports exactly one
      importer (the tool lives inside it)
- [ ] `check_no_hardcoded_context_budgets.sh` clean (token budgeting adds no
      literal)
- [ ] Unaccepted lens proposal does not reach `fromLocalProfile()`

## Regression Guards

- **REQ-INT-001 / P3** — the tool type, its `Arguments`, and any
  `Transcript.ToolDefinition` construction live inside
  `FoundationModelsIntelligenceService.swift`. `EntryRetriever`,
  `RetrievalPolicy`, and the new gate remain FoundationModels-free.
- **REQ-INT-017 / spec 039** — no tool, no exemplar, and no suffix longer
  than six lines is ever attached to phatic, continuer, companion, meta, or
  redirect turns. The effort curve is a unit-tested property of
  `ReplyChannel`, not a prompt promise.
- **Spec 037 rule 3** — the model still never counts. Passage retrieval and
  tools change *what evidence* the model sees, not what it may claim about
  it; `AskAnswer`'s `@Guide` bans are untouched.
- **Spec 037 "goals are not the subject"** — `confirmedThemeIds` never
  enter instructions or the user prompt. They reorder evidence only.
- **Spec 026** — `SafetyRouter.decide` runs on the user message before
  retrieval *and* on every tool `query` before that retrieval. Crisis and
  hard-refuse never pull journal text into a prompt.
- **REQ-PRIV-001** — passage vectors, the retrieval report, and the lens
  proposal are on-device artefacts. The retrieval gate reads fixtures only;
  043's `is_fixture_id_array` rejects journal UUIDs in imported rows.
- **Spec 017 R9** — sessions stay stateless and single-use; the speculative
  fingerprint contract in `AskTranscriptPlan` is extended (exemplar entry),
  not bypassed.
- **CONSTITUTION §4 rule 5** — no context-window literal anywhere;
  `charsPerToken` remains a documented fallback and `tokenCount` is the
  source when present.
