# 044 + 045 — Implementation sessions

How to land [`044`](../044-agentic-harness-depth.md) and
[`045`](../045-computed-insights-and-period-reflection.md) without
breaking the rest of the corpus. One session ≈ one PR. Do not skip Session 0.

**Corpus review (2026-09-06)** found six conflicts. Session 0 is the
amendments; they are already written into 022 / 038 / 044 in this PR.
Implementers still verify they landed before writing Swift.

## Standing constraints (every session)

| Rule | Source | Practical effect |
|------|--------|------------------|
| Exactly one `import FoundationModels` | CONSTITUTION §4.5, 017 R1 | New `@Generable` types, `Tool`, and `LanguageModelSession` construction live in `FoundationModelsIntelligenceService.swift` only |
| No context-window literals | CONSTITUTION §4.5 | Use `ContextBudget` / `tokenCount`; `charsPerToken` is fallback only |
| Safety before any journal text enters a prompt | 026, 044 R4, 045 R3/R4 | `SafetyRouter.decide` on the user message, every tool `query`, and entry/weekly blobs |
| Model never counts | 037 rule 3, 045 R1 | Numbers live in `InsightFact.n` and chart chrome |
| Goals are not the subject | 037, 038 R6 (amended) | `confirmedThemeIds` never enter instructions; `themeBoost` reorders only |
| Code decides, model renders | 037 / 039 / 044 | No ReAct, no `.required` tools, no Dynamic Profiles |
| Sessions stay stateless | 017 R9 | Extend `AskTranscriptPlan` fingerprints; do not keep a live session |
| New `@Model` properties need a migration | CONSTITUTION §4.2 | Prefer existing optional columns / `ExperienceProfile` JSON |
| Tests in the same PR as behavior | `.cursor/rules/testing.mdc` | Contract tests update in the prompt-change PR, not later |
| Content-free logs | CONSTITUTION §4.3 | Perf line may add `prompt_tokens` / `tools=N`; never query text |

## Session 0 — Spec amendments (docs-only, this PR)

Already done if you are reading this on the branch that added 044/045:

- 038 R3 / R6 / Non-goals — bounded `themeBoost` allowed; three-layer lens caps.
- 022 R2 — TrajectoryExpectation is **retrieval occurred**, not tool-called.
- 044 — `harness_retrieval` kind; `AskResult.toolsCalled`; 038/022 citations.
- 045 minted; 019 R5 still names `SpotlightSearchTool` — Session 9 amends it
  after Branch B is real.

**Verify before Session 1:** `python3 scripts/ci/lint_forbidden_phrases.py`.

---

## Phase I — Evidence (044 R1–R3). iOS 26 SDK. No live model in CI.

### Session 1 — Passage index (044 R1)

**Files (new):**
- `MeetMemento/Services/Intelligence/PassageChunker.swift` — `NLTokenizer(unit: .sentence)`, merge to 120–400 chars, never split mid-sentence; `NLLanguageRecognizer` once per entry.
- `MeetMementoTests/PassageChunkerTests.swift`

**Files (edit):**
- `EmbeddingService.swift` — cache key `(entryID, passageIndex, contentHash)`; keep whole-entry vector as fallback. Re-embed only changed passages.
- `EntryRetriever.swift` — score `max(passage cosine) + 0.15 * mean`; `RetrievedEntry.text` = best passage + one neighbour sentence each side, cap `maxContentChars`; `quotedSpan` from that passage.
- `EntryRetriever.warmEmbeddings` — drain passages on the existing utility queue.

**Do not touch:** `PromptRegistry`, `ReplyChannel`, `FoundationModelsIntelligenceService` prompt assembly, citation reconciliation API.

**Tests:** chunk boundaries; edit invalidates only changed passages; a 900-word fixture whose gold span is past char 500 appears in `contextBlock`. `ConversationalRecallContractTests` 3–5 cap still holds (`RetrievalLimits` unchanged).

**Done when:** unit tests green; `check_single_intelligence_importer.sh` still 1; no generation behavior change.

### Session 2 — RetrievalGate + fitted weights (044 R2)

**Files (new):**
- `MeetMementoTests/Eval/RetrievalGate.swift` — `TEST_RUNNER_RETRIEVAL_GATE=1`, no model. Load `Fixtures/gold/questions.resolved.json` + `Fixtures/corpus`. Report recall@5, precision@5, MRR, abstention accuracy (`match: "none"` → `.empty` or ambient, never a strong hit). Write `.eval-runs/retrieval/`.
- `scripts/eval/fit_retriever.swift` (or `RETRIEVER_GRID=1` on the same test) — grid `RetrieverTuning` + hybrid weights + `themeBoost`.

**Files (edit):**
- `EntryRetriever.swift` — commit the **winning** weights with the grid output in the PR body.
- `scripts/eval/import_run.sh` — confirm `kind=harness_retrieval` (already in the 043 enum). Do not add `retrieval_gate`.
- `.github/workflows/ios-build-online.yml` — wire the gate **report-only** (no `XCTAssert` threshold yet).

**Thresholds:** two measured runs warehoused, then arm `recall@5 ≥ 0.85` and abstention ≥ 0.90 (044 R2 / 022). Do not invent a bar from the first run.

**Done when:** gate runs on a Mac with no Apple Intelligence; before/after recall table is in the PR; no gold item flips hit → miss vs Session 1.

### Session 3 — Theme priors + starters (044 R3)

**Depends on:** Session 0's 038 amendment.

**Files (edit):**
- `EntryRetriever.swift` — `themeBoost` (default from the Session 2 grid, else 0.5). Match `ThemeCatalog.synonyms` against passage text. Boost applies only after `hasSignal`. No boost on ambient.
- `ThemeAwareChatStarters.swift` — delete "Create an actionable plan…"; replace mood-shift / plan fallbacks with archivist quantitative templates (045 R5 owns the wording; land the copy here so the empty state is honest in the same PR). Gate a themed starter on ≥ 3 entries in that theme's cluster when Session 1 vectors exist; otherwise keep today's rotate.
- `scripts/ci/lint_forbidden_phrases.py` already covers these strings.

**Tests:** two-way tie + `relationships` confirmed → relationships entry ranks first; no confirmed themes → order unchanged. Lint clean.

**Do not:** inject theme ids into `PromptRegistry` or `[Turn:]` lines.

---

## Phase II — Facts the model is not allowed to invent (045 A + R5)

Ship this **before** the lean prompt so Chat can answer quantitative
questions on the current `ask@15` path. Independent of iOS 27.

### Session 4 — InsightEngine + Patterns (045 R1, R2)

**Files (new):**
- `MeetMemento/Services/Intelligence/Insights/InsightFact.swift`
- `MeetMemento/Services/Intelligence/Insights/InsightEngine.swift`
- `MeetMementoTests/InsightEngineTests.swift` — golden cadence / people on `Fixtures/corpus`, including sparse weeks → low-confidence (`n < 4`).

**Files (edit):**
- `WeeklyReflectionView.swift` `PatternsView` — charts from facts; every correlation shows `n`; low-confidence copy.
- `KeywordsCard.swift` / `SentimentAnalysisCard.swift` — adopt into the tab **or delete in this PR** (019 R4 ledger). Do not leave zombies.

**Valence trends wait for Session 6.** Clusters use whatever vectors exist (whole-entry or passages).

**Done when:** Insights folder has zero `import FoundationModels`; Patterns tab is interactive with no generation.

### Session 5 — Quantitative Ask (045 R5)

**Files (edit):**
- `TurnClassifier.swift` — high-precision quantitative patterns (`how many` / `how often` / `when did I last` / `how has X changed`). Must not steal `journalQuery` ("what did I write about sleep?"). Precision-biased, same as today's social rules.
- `ReplyChannel.swift` — `.statistic`: `allowsRetrieval = false`, 64 tokens, temp 0.9, `usesLightPrompt` true or a tiny suffix — **do not** load `ask@15` at 512 tokens for a count.
- `IntelligenceService.swift` / `ChatService.swift` / `ChatViewModel.swift` — carry `[InsightFact]` on `.delta` the way `reviewedCitations` already ride.
- `AIOutputComponent.swift` — stat section with `n` and tap-through IDs; can mount before body text (empty-streaming-placeholder already treats citations as enough to show).
- `ChatEvalScoring.swift` — add `insight.*` family, **not gated** until Session 10.

**Tests:** classifier unit tests (quantitative vs journalQuery vs offdomain). View-model test with `MockChatService` emitting a fact. "How many times did I write about my brother this year?" against fixtures shows the Swift `n`.

**Channel exhaustiveness:** `ReplyChannel` is `CaseIterable` and 039 tests walk it — add the row, do not skip a rank (039: skipping a rank is a spec violation).

---

## Phase III — Prompt (044 R5)

### Session 6 — `ask-core@16` + contract test updates

**Files (edit):**
- `PromptRegistry.swift` — split `ask` into `ask-core@16` + five channel suffixes (notebook / thread / companion / meta / redirect), each ≤ 6 lines. `ask-degraded@16`. Light prompts unchanged (`chat-light@4`).
- `PromptStanceSyncTests.swift` — assert each **suffix** contains every `TurnStance.tagPrefix` that channel can produce (not the core).
- `AskPromptContractTests.swift`, `ConversationalRecallContractTests.swift`, `PromptRegistryResolutionTests.swift`, `PromptPersonalizationTests.swift` — bump `ask@15` → `ask-core@16` / `+p4` pins in the **same PR**.

**Do not enable** the exemplar turn or `includeSchemaInPrompt: false` in this PR. Land the split first so ChatEvalGate has a clean A/B.

**Eval:** warehoused `ChatEvalGate` run vs the last `ask@15` baseline (043, distinct `prompt_version`). Keep only if 100% and notebook `prompt_tokens` is on a path to ≤ 55% (may need Session 7's token log to prove; until then compare instruction character count).

**Done when:** contract tests green; `ChatEvalGate` 100% on device/eval lane (not merge-lane).

### Session 7 — Exemplar + schema A/B + token budget (044 R5 experiments, R7)

**Files (edit):**
- `AskTranscriptPlan.swift` — optional synthetic first pair on notebook + empty history; never written to `LocalChatStore` (guard test).
- `FoundationModelsIntelligenceService.swift` — `ContextOptions(includeSchemaInPrompt:)` flag; `tokenCount(for:)` when `compiler(>=6.3)` / iOS 26.4+; `logOutcome` gains `prompt_tokens`, `cached_tokens`, `tools=N`.
- `ContextBudget.swift` — `init(tokenCounts:)` ; `charsPerToken` remains the `.unavailable` path.

Kill-switches in `PromptRegistry` / a debug flag. Two warehoused runs each. Record keep/kill **in 044** (dated amendment), not only in chat.

---

## Phase IV — Tags and weekly (045 B, C)

### Session 8 — Entry reflection (045 R3)

**Files (edit):**
- `IntelligenceService.swift` — `GenerationIntent.entryReflection`; `reflect(on: Entry) async throws -> GenerationOutcome<EntryReflection>` (or a dedicated result type carrying 017's fields + zone).
- `ModelRouter.swift` — Z0, `degradedZone: nil`, `.interactive`.
- `PromptRegistry.swift` — `entry-reflect@1`.
- `FoundationModelsIntelligenceService.swift` — `@Generable EntryReflection` **verbatim** from 017 R5; closed `MoodLabel` / `TopicLabel`; safety first; quiet refusal.
- `EntryViewModel.swift` — after `createEntry` / `updateEntry` commits, `Task.detached(priority: .utility)`.
- `MementoDataStore.swift` — write `moodLabels` + `StoredReflection(kind: .entry)`.
- Backfill on the embeddings warm queue; `RefusalOutageTracker` stops a broken asset.

**014:** persist `zoneRaw` / prompt version. No UI disclosure on the quiet path (019 R2: refusal == omitted observation).

**Tests:** `ModelRouterTests` will fail until the row exists — add it in this PR. Save-failure leaves transcript identical. `RestraintGate` report-only: observation suppressed rate on ordinary fixtures.

### Session 9 — Weekly reflection, foreground (045 R4)

**Files (edit):**
- `GenerationIntent.weeklyReflection` — default Z1 `.moderate`, degraded Z0 (today `.sdkUnsupported` → Z0, `wasDegraded: false`).
- `PromptRegistry` — `weekly@1` / `weekly-degraded@1`. Observation `@Guide` already bans advice / questions / comfort (017).
- `JournalView` appear — if previous ISO week uncovered and `n ≥ 1`, generate; card shows "writing now…".
- `WeeklyReflectionStore.save` + existing CloudKit upsert.
- Card: citations tap to `Entry` (new UI; do not revive deleted `InlineCitationBadge` — 019 said they stay dead; use a dated list like Ask's sheet or a simple `NavigationLink`).
- Thumbs → `ratingRaw`. `SpeakabilityLinter` on body + observation.
- `ReadWeeklyReflectionIntent` — no API change if `latestBody` is written.

**Do not** register `BGProcessingTask` or a third notification identifier (019 R8 / "exactly two notifications in the app").

**Amend 019 R5** in this or the next docs PR: replace `SpotlightSearchTool` with "044 `SearchJournalTool` + 045 `InsightEngine`" as the Branch B implementation.

**Tests:** sparse week → `hasNothingToSay`, week marked covered. Citation tap-through UI test on fixtures.

---

## Phase V — Agency (044 R4). Xcode 27 / iOS 27 SDK.

### Session 10 — `SearchJournalTool`

**Files (edit, inside the single importer):**
- `SearchJournalTool: Tool` with `@Generable Arguments { query, when }`.
- Attach instances only when `channel.allowsRetrieval`. `toolCallingMode = .allowed`.
- Hard cap 2; third call returns authored "no further search this turn".
- `SafetyRouter.decide` on `query` before `EntryRetriever.retrieve`.
- Ingest into `SessionCandidatePool`; re-number refs; `reconcileCitations` unchanged.
- `AskResult.toolsCalled: Int` (041 / 044 amendment).
- `AskTranscriptPlan` / `makeSession` — `toolDefinitions` from the instance when attached.
- `#if compiler(>=6.3)` + `@available(iOS 27.0, *)` — same pattern as image attachments. iOS 26 path unchanged.

**Tests:**
- Phatic built transcript has zero tool definitions.
- Scripted third call → exactly two `retrieve`s.
- `AgenticEval` multi-hop probes (report-only, two runs, then consider gating).
- 022 R2 amended: notebook gold items pass if **pre-retrieval ran**, even when `toolsCalled == 0`.

**Eval:** do not arm "tool called on 100% of notebook turns".

---

## Phase VI — Living profile (044 R6)

### Session 11 — Consent-gated lens refresh

**Depends on:** Session 1 clusters; Session 8 topics improve the input but are not required.

**Files (edit):**
- `GenerationIntent.profileRefresh` — Z0, no degraded leg, `priority: .scheduled` (017 R3: scheduled outranks interactive if quota ever exists).
- `PromptRegistry` — `profile-refresh@1` (reuse `ProfileEstimateAnswer` + `ThemeCatalog.validate`).
- Cadence: ≥ 14 days since `builtAt` and ≥ 10 new entries; trigger on Journal appear at `.utility`; never during Ask.
- `ExperienceProfile` — optional `proposedPromptLens`, `proposedModelIdentifier`, `proposedPromptVersion` (Codable JSON — **no** SwiftData `@Model` change).
- Settings → Profile: current lens, proposal, Accept / Edit / Keep mine. Unaccepted proposal must not reach `PromptPersonalization.fromLocalProfile()`.
- `OutputSafetyScanner` + forbidden-phrase lint; hit discards silently.
- Honour `aiEnabled` / `processOnDeviceOnly`.

**014:** this is a generation surface. Persist provenance on the proposal. Settings is the point of use; no chat disclosure needed until accepted.

**Tests:** unaccepted proposal unused in Ask; `ModelRouterTests` exhaustiveness; `PersonaGate` no-advice on the proposal text.

---

## Phase VII — Close the loop

### Session 12 — `[Computed]` on notebook + arm gates

- Attach non-suppressed `InsightFact`s as a `[Computed]` prompt block on notebook turns (045 R5 D / 044 Phase 3+).
- Valence trend facts now that Session 8 has tags.
- Arm `insight.*` in `ChatEvalScoring.gating()`.
- Arm `RetrievalGate` thresholds if two report-only runs exist.
- Arm `RestraintGate` if Session 8/9 data exists.
- Record keep/kill for Session 7 experiments in 044.

---

## Suggested PR graph

```text
Session 0 (docs) ─┬─► 1 (passages) ─► 2 (gate+fit) ─► 3 (themeBoost)
                  │
                  └─► 4 (InsightEngine) ─► 5 (quantitative Ask)
                                              │
1 ─► 6 (ask-core@16) ─► 7 (A/B + tokens)
                                              │
5 + 6 ─► 8 (entry reflect) ─► 9 (weekly)
                                              │
6 + 1 ─► 10 (SearchJournalTool, iOS 27)
1 + 8? ─► 11 (living profile)
9 + 10 + 7 ─► 12 (close loop, arm gates)
```

Sessions 1–5 can overlap after Session 0. Session 10 is the only one
blocked on Xcode 27. Session 11 is last among product-facing work because
it writes the person's lens.

## What you explicitly do not do

- Do not attach tools to phatic / continuer / companion / meta / redirect (039).
- Do not use `SpotlightSearchTool` (016 Branch B / DEC-002).
- Do not adopt Dynamic Profiles (044 R4 note / 017 R9).
- Do not schedule `BGProcessingTask` or add a notification (019 R8, "exactly two").
- Do not put confirmed themes in L1 (037 / 038).
- Do not widen `AskAnswer` for facts — they ride the stream event, like citations.
- Do not make `citedRefs` required again (importer comment, 2026-08-23 grid).
- Do not implement monthly `.deep` or PCC in these sessions.
- Do not revive `InlineCitationBadge` / `CitationFlowText` (deleted 2026-08-27).
