# 046 + 047 + 048 — Implementation sessions

How to land [`046`](../046-grounding-and-evidence-discipline.md),
[`047`](../047-conversational-state.md) and
[`048`](../048-harness-depth-ii.md) without breaking the rest of the corpus.
One session ≈ one PR. Do not skip Session 0.

**Where these came from (2026-09-20).** A 200-conversation self-play study
(6,984 messages; 100 conversations against the 8-entry cold-start journal and 100
against a **zero-entry** journal) ran the Ask pipeline at 20–50 messages per
conversation for the first time. Raw data:
`.eval-runs/convo-sim/full-2026-09-20.jsonl`. Harness:
`withMementoTests/Eval/ConversationSimulation.swift` on branch `convo-sim-harness`
(commits `e4d1621`, `ad59c95`).

**The study measured a pipeline that already had most of 044.** `PassageChunker.swift`
(044 R1), `RetrievalGate.swift` (044 R2) and `ask-core@17` (044 R5) are all in the
tree, despite 044's front matter still reading `draft`. Session 0 corrects that
first, because the workflow protocol tells the next session to pick the
lowest-numbered spec whose dependencies are done — and it would re-do landed work.

## Standing constraints (every session)

| Rule | Source | Practical effect |
|------|--------|------------------|
| Exactly one `import FoundationModels` | CONSTITUTION §4.5, 017 R1 | New `@Generable` fields and the `evalRawGenerate` eval seam live in `FoundationModelsIntelligenceService.swift` only |
| Code decides, the model renders | 037 / 039 / 044 | A rule that must hold is schema selection or reconciliation, never `@Guide` prose asking the model to restrain itself |
| A scorer must prove it can fire | 046 R1 / 048 R1 | Pattern-compile assertion + one positive fixture per violation code, from Session 1 onward |
| Measure first, threshold after | technology/04-evaluations.md, 044 R2 | New and repaired checks land report-only; two warehoused runs before any bar |
| No context-window literals | CONSTITUTION §4.5 | Use `ContextBudget` / `tokenCount` |
| Safety before any journal text enters a prompt | 026 | Unchanged by all three specs; `SafetyRouter.decide` still runs first |
| Model never counts | 037 rule 3, 045 R1 | The `statistic` path stays Swift-computed and is out of scope |
| Sessions stay stateless | 017 R9 | No live `LanguageModelSession` is retained |
| Tests in the same PR as behavior | `.cursor/rules/testing.mdc` | Prompt-contract tests update in the prompt-change PR, not later |
| Content-free logs | CONSTITUTION §4.3 | Evidence state may be logged; spans, entry text and query text may not |

**Verify before Session 1:** `python3 scripts/ci/lint_forbidden_phrases.py` and
`bash scripts/ci/check_single_intelligence_importer.sh`.

---

## Session 0 — Spec amendments and status truth (docs-only)

- Correct 044's and 045's `status:` — R1/R2/R5 and `InsightEngine` have shipped.
  Either mark them `in-progress` with the landed requirements ticked, or `done` where
  the acceptance criteria are met. Leave the unshipped parts (044 R4 tool loop,
  044 R6 living profile) visible.
- Register 046/047/048 in `specs/README.md` and add the phase row to `ROADMAP.md`.
- No Swift.

**Done when:** a reader picking work off `ROADMAP.md` can tell what is actually built.

---

## Phase I — Detection integrity (046 R1–R2). Test target only. No app change.

### Session 1 — Repair the fabrication scorer (046 R1)

**Files (edit):**
- `withMementoTests/Eval/ChatEvalScoring.swift` — fix the `fabricatedQuotes` pattern
  (`\u{201C}` → `\x{201C}`, `\u{201D}` → `\x{201D}`; a Swift raw string does not
  process `\u{…}` and ICU rejects it). Keep `hall.fabricatedQuote` **report-only**
  for now.

**Files (new):**
- `withMementoTests/ChatEvalScoringTests.swift` — one positive fixture per violation
  code, plus a test that every regex used by the file compiles.

**Do not touch:** any file under `withMemento/`. This session changes no app
behaviour.

**Tests:** the repaired scorer fires on a fabricated italic span and stays silent on
a body with no italics; a deliberately broken pattern fails a named test.

**Done when:** replaying `.eval-runs/convo-sim/full-2026-09-20.jsonl` through the
repaired scorer fires on the 202 empty-arm turns carrying a matching span, and the
count is recorded in the PR body. Expect a burst of cold-arm findings too — that is
detection appearing, not quality regressing. Say so in the PR description.

### Session 2 — Empty-corpus semantics (046 R2)

**Files (edit):** `ChatEvalScoring.swift` — pin `QuoteIndex([])` behaviour; implement
"no entries ⇒ every journal-material span is fabricated," reusing the existing
verbatim matcher rather than adding a second one.

**Do not touch:** `EntryRetriever`, `reconcileCitations`.

**Done when:** `contains`, `quotesCorpus`, `fabricatedQuotes`, `uncitedQuote` and
`boldNotTheirWords` each have an empty-corpus fixture pinning the intended outcome.

---

## Phase II — Evidence decides the form (046 R3–R4). App change. Prompt version bump in Phase III.

### Session 3 — Evidence state and channel resolution (046 R3)

**Files (new):** the evidence-state type (plain Swift, no new `FoundationModels`
importer).

**Files (edit):**
- `ReplyChannel.swift` — `resolve` takes evidence state; an empty archive can never
  resolve to `notebook` or `thread`.
- `FoundationModelsIntelligenceService.swift` — compute the state at `:924`;
  `stanceMatchingEvidence` (`:1928`) becomes a no-op for the empty-archive case
  rather than a corrector.
- `withMementoTests/DiagTurnRouting.swift` — report evidence state per row.

**Do not touch:** `EntryRetriever` ranking, `PromptRegistry` text, `AskAnswer`.

**Ordering note:** the archive-empty test needs no retrieval and runs at
classification time. The `.ambient` / `.matched` split is only knowable after
`retrieveWide`, so a non-empty archive may refine afterwards — refinement may only
downgrade *out* of `notebook`, never upgrade into it.

**Done when:** zero-entry `journalQuery` turns route to a non-notebook channel and
`RetrievalPolicyTests` / `ConversationFlowTests` still pass.

### Session 4 — Withhold the form (046 R4)

**Files (edit):**
- `ReplyChannel.swift` — `usesBodyOnlySchema` becomes evidence-aware as well as
  spokenness-aware.
- `FoundationModelsIntelligenceService.swift` — strip *"only if this turn uses the
  journal"* from `AskAnswer.body`'s `@Guide`; the schema is now only offered when the
  turn does use the journal.
- `withMementoTests/AskPromptContractTests.swift` — guide assertions, same PR.

**Done when:** an empty-archive reply is decoded from `LightAskAnswer` and carries no
`###`, no italic span and no citations. This is the session that should move the
13.1% fabrication rate; measure it with a fresh zero-entry arm before closing.

---

## Phase III — The contract (046 R5–R6). Schema change.

### Session 5 — Evidence-typed claims and the version bump (046 R5, R6)

**Files (edit):**
- `FoundationModelsIntelligenceService.swift` — add the evidence-reference field to
  the Ask schema. **Optional and trailing**, with a Swift-side fallback: making
  `citedRefs` required previously dropped decode success 5/5 → 4/5 (recorded at
  `:69-84`), and `body` must keep leading the decode order (029 Amendment A).
  Converge on the `groundedEntryIDs` shape `EntryReflection` / `PeriodReflection`
  already use (`:148-175`) rather than inventing a parallel one.
- `PromptRegistry.swift` — `ask-core@17` → `@18`, `ask-degraded@17` → `@18`.
- `AskPromptContractTests.swift`, `PromptStanceSyncTests.swift`,
  `PromptRegistryResolutionTests.swift` — same PR.

**Done when:** a fact claim with no resolvable evidence is detectable on an empty
archive; a decode that drops the field still renders the body and records the turn as
unverified; `AskLatencyFloorTests` unchanged.

---

## Phase IV — The instrument (048 R1–R3). Test target only.

### Session 6 — Scorer coverage and route coverage (048 R1, R2)

**Files (edit):** `ChatEvalScoringTests.swift` (coverage test that fails on an
uncovered code); `DiagTurnRouting.swift` / `Eval/PromptSweepRouting.swift` — emit a
`TurnType` × `ReplyChannel` matrix including zero rows.

**Do not touch:** app targets.

**Done when:** a `TurnType` observed zero times is reported explicitly. This is the
gate that makes Session 7 safe.

### Session 7 — Counterfactual pairs (048 R3)

**Files (new):** paired worlds with ground truth and forbidden claims — entity
present/absent, truth decay, evidence recent/old, one entry vs five near-duplicates.
Build on `ChatEvalCorpus`.

**Budget note:** generation is serial (`ModelRuntimeGate` holds a lock); the study
measured 2.06s p50. Roughly 300 pairs per 20 minutes. Do not design for six-figure
sample counts — and do not mock the generator to reach them, because none of the
defects in 046 or 047 would have been detectable that way.

---

## Phase V — Conversational state (047). App change, behind the instrument.

### Session 8 — Ungate follow-up detection (047 R1)

**Files (edit):**
- `ChatViewModel.swift:432` — compute `answeringLastQuestion` from conversation
  state, not `origin == .narration`.
- `FoundationModelsIntelligenceService.swift:914` — same, not `spoken`.
- `withMementoTests/Eval/ConversationSimulation.swift:191` — **the harness has its own
  copy of this defect**; without this line the fix will not appear in a re-run.
- `TurnClassifierTests.swift` — extend the existing `lastAssistantAskedQuestion` fork
  cases; do not re-prove the fork works.

**Do not touch:** the follow-up phrase lexicon. The gate, not the lexicon, is the
constraint.

**Done when:** report-only, two warehoused runs, routing delta in the PR body. Adopt
in a follow-up PR once the matrix shows the effect.

### Session 9 — Correction handling (047 R2, R3)

**Files (edit):** `TurnClassifier.swift` (new turn type, tested after
social/acknowledgement/meta and before the `share` default), `RetrievalPolicy.swift`
(stance), `PromptRegistry.swift` (channel suffix entry), `ChatEvalScoring.swift`
(acknowledgement + retraction scorers with fixtures).

**Watch for:** widening into ordinary disagreement. "I don't think that's why I was
tired" is reflection about the person's own life, not a correction of an assistant
claim.

---

## Phase VI — Durability (048 R4–R6).

### Session 10 — Failure corpus, standing harness, warehouse

**Files (new):** the failure-corpus directory and its promotion path.

**Files (edit):** fold `ConversationSimulation` into the eval corpus, preserving both
properties it needed — the simulator's own guardrail must not truncate a
conversation, and a designed refusal must not end a run. Wire reporting into the
`043` warehouse under an existing `kind`.

**Done when:** a promoted failure reproduces without the original run artifact, and
`scripts/eval/import_run.sh` accepts the run with `--prompt-version` and `--model`.

### Session 11 — Arm thresholds

Only now. Each armed threshold cites **two** warehoused runs in the PR body. A
threshold proposed from a single run is rejected — including for
`hall.fabricatedQuote`, whose true rate nobody has ever seen.

---

## Evidence-first program (spec 049) — S0–S13

These sessions land 046–048 and the scorecard in
[`049`](../049-epistemic-voice-and-response-policy.md). Do not skip ahead:
later sessions assume the scorer and the evidence gate already exist. Standing
rules above apply to every session. The voice stays. 049 forbids flattening
imagery, short sentences, or quiet language.

| Session | What changes | Done when |
|---------|--------------|-----------|
| S0 | Docs only. Tick 044 R1/R2/R5 and 045 `InsightEngine`. Leave 044 R4 and R6 open. Add 049. Amend 039 (Open only on `reflect`), 046 (delete the nearbyOnly hedge), 047 (interpretation-cut). Register 049 on the roadmap. | A reader of the roadmap can tell what is built and what these sessions will change |
| S1 | `AskPipeline` thin wrapper. No behavior change. Header lists safety, response policy, evidence ladder, retrieval, prompt, generate, epistemic guard. | Pipeline test matches today's `ReplyChannel.resolve` for each `TurnType`, including the photo bump. No prompt snapshot changes |
| S2 | Test target only. Repair `hall.fabricatedQuote` (`\x{201C}` / `\x{201D}`). Add `hall.firstPersonPerception` and `hall.narrativeJoin`. Report-only. | Every regex compiles. Each `hall.*` / `rule.*` code has a fixture. Replay counts recorded |
| S3 | Test target only. `QuoteIndex([])` treats an italic span or `###` heading as fabricated, reusing `quotedRefs`. | Fixtures cover `contains`, `quotesCorpus`, `fabricatedQuotes`, `uncitedQuote`, `boldNotTheirWords`. A reply with none of those spans emits nothing |
| S4 | `EvidenceState` (`.none` / `.ambient` / `.matched`) gates `ReplyChannel`. A `journalQuery` on `.none` is never `notebook` or `thread`. | A zero-entry journal question cannot resolve to notebook |
| S5 | `.none` decodes `LightAskAnswer`. Delete the self-assessing `@Guide` clause. | `test_spokenNotebook_usesBodyOnlySchema` still passes. Empty archive cannot emit `###`, italics, or `citedRefs` |
| S6 | `EvidenceLadder` writes one prompt line. Delete the nearbyOnly hedge. Bump `ask-core@17` and `ask-degraded@17` to `@18`. | Inventory with hits uses `exact` or `strong`. A miss is `none` with no nearest-entry quote. Core stays inside the size budget |
| S7 | `QuestionShape` and `ResponsePolicy`. "Last Tuesday" and "before the pottery class" filter `createdAt`. One suffix per policy. | Advice opener is `list`. Goodbye is `acknowledge`. Pottery is not ranked first when earlier entries exist |
| S8 | Ungate `answeringLastQuestion`. `TurnType.correction` selects `retract`. Interpretation-cut also retracts and stores the claim. | A correction is never `guardrailRefusal`. Follow-up rate, thread share, and correction rate are recorded. No threshold armed |
| S9 | One light retry for ordinary refusals on `share` or `social`. Move the safety line into the regulated-advice suffix. Strip harness markup before the bubble is stored. Quantitative labels are real subjects. | Three consecutive refusals still go unavailable. `extractSubject` does not label a card `from`, `the`, or `didn` |
| S10 | `HistoryWindow`: summary plus last 4 turns plus the current message. Notebook also gets evidence passages. `.none` skips retrieval and adopts the prewarmed light session. Cap cuts end on a sentence boundary. | Narration stays on `askStream`. `AskLatencyFloorTests` stays green |
| S11 | Route matrix, counterfactual pairs, failure corpus. Re-run one zero-entry arm and one cold arm against the September log. | A `TurnType` at zero is reported. Thresholds wait for two warehoused runs |
| S12 | `SearchJournalTool` on `notebook` and `thread` only, two calls max, after S6 abstention. On-device passage downrank from thumbs-down, purged when the entry is deleted. | Phatic, companion, and redirect never see a tool. No derived fact enters the evidence block without source entry ids |
| S13 | Move files into `Routing/`, `Evidence/`, `Retrieval/`, `Prompt/`, `Reconciliation/`. No logic change. `AskPipeline.swift` and the intelligence service stay at the intelligence root. | `check_single_intelligence_importer.sh` still reports 1. Forbidden-phrase lint stays clean |
