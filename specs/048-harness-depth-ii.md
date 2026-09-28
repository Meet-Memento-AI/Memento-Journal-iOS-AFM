---
id: 048
title: Harness Depth II — Self-Testing Scorers, Route Coverage, Counterfactual Worlds
tier: P2
status: draft (2026-09-20)
effort: 4–5 sessions
depends_on: [022, 043, 044, 046, 047]
findings:
  - scorer-can-fail-silently-forever
  - no-route-coverage-measurement
  - single-world-fixtures-cannot-isolate-a-cause
  - failures-evaporate-after-the-run
  - long-form-conversation-was-never-measured
source_refs: [REQ-HAR-001, REQ-HAR-002, REQ-HAR-003, REQ-HAR-004, REQ-HAR-005, REQ-HAR-006, REQ-EVAL-001, REQ-PRM-004]
tech_refs: [technology/04-evaluations.md, technology/01-foundation-models.md]
---

# 048 — Harness Depth II

**Traceability:** extends the evaluation machinery that spec
[`022`](022-evaluation-and-quality-study.md) owns, with run identity from
[`043`](043-eval-run-warehouse.md) and retrieval measurement from
[`044`](044-agentic-harness-depth.md) R2. It is the instrument for
[`046`](046-grounding-and-evidence-discipline.md) and
[`047`](047-conversational-state.md): 046's restored scorer and 047's routing
migration are both unfalsifiable without R1 and R2 here. Mints the **`REQ-HAR-`**
series inline.

**Does not implement:** anything in the app. Every requirement is test-target only.

## Why

The 2026-09-20 study found two defects that existed for as long as the code did and
that no gate could ever have reported. A gating scorer whose regex could not compile
returned empty for every input and read as a pass (`046` finding 1). A turn type
fired on 0.14% of turns and took an entire retrieval path down with it (`047`
finding 2). Neither is exotic; both are invisible to a suite that only asserts on
outputs it already expects.

The study also showed what *did* find them: not volume, but **contrast** — two worlds
differing in one property (a journal, or none), run long enough for conversational
state to matter. That result should be the harness's shape.

Tier P2: this is test infrastructure and blocks no gate directly, but `046` cannot be
verified without it.

## Technology References

- `technology/04-evaluations.md` — the gate posture this spec enforces procedurally:
  measure first, threshold after; a bar picked before the first measurement is a
  guess.
- `technology/01-foundation-models.md` §3 — generation cost. Relevant because R3
  rejects volume-based designs on measured throughput grounds, not taste.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Verified 2026-09-20.

| # | Finding | Evidence | Severity |
|---|---------|----------|----------|
| 1 | **A scorer can fail silently and permanently.** `spans()` is `guard let re = try? NSRegularExpression(pattern:) else { return [] }`. No test asserts any pattern compiles; no `hall.*` scorer has a positive fixture. One scorer has been dead since it was written. | `ChatEvalScoring.swift:220-224` (`spans`), `:236` (the pattern) | **Critical** |
| 2 | **No route-coverage measurement exists.** `DiagTurnRouting` and `PromptSweepRouting` dump routing decisions but assert nothing about coverage, so a turn type that stops firing produces no signal. | `withMementoTests/DiagTurnRouting.swift`, `withMementoTests/Eval/PromptSweepRouting.swift:44` | High |
| 3 | **Fixtures are single worlds, so a cause cannot be isolated.** `Fixtures/corpus` is one 262-entry persona and `Fixtures/cold-start` is one 8-entry journal. Nothing pairs two worlds differing in exactly one property, which is what exposed the fabrication finding. | `Fixtures/`, `ChatEvalCorpus.swift` | High |
| 4 | **Failures evaporate.** A failing generation exists only as a row in `.eval-runs/`; nothing promotes it to a checked-in case, so a fixed defect can regress silently. | `ChatEvalGate.swift:315` (`write`), `AgenticEval.swift:548` (`flush`) | Medium |
| 5 | **Long-form conversation was never measured until this study.** `ChatEvalGate` scores one generation; `AgenticEval` plays short scripted probes. The 20–50 message shape — where the 24-message history window closes mid-conversation — had no coverage. | `ChatEvalGate.swift:102`, `AgenticEval.swift:96-110`, `ChatService.swift:558` | Medium |
| 6 | **Generation is strictly serial.** `ModelRuntimeGate` holds a lock around every call; the study measured 2.06s p50 per generation, unchanged by conversation count. Any design assuming parallel scale is not executable on this runtime. | `ModelRuntimeGate.swift`; `.eval-runs/convo-sim/full-2026-09-20.jsonl` | — (constraint) |

## Requirements

**Traceability:** R1 → `REQ-HAR-001`; R2 → `REQ-HAR-002`; R3 → `REQ-HAR-003`;
R4 → `REQ-HAR-004`; R5 → `REQ-HAR-005`; R6 → `REQ-HAR-006`. All test-target only.

### R1. Scorers prove they can fire (`REQ-HAR-001`)

Generalises `046` R1 into a standing rule: no scorer may be added or modified without
(a) an assertion that its pattern compiles and (b) a positive fixture that makes it
emit its own code. A gating check that cannot fire is worse than no check, because it
reads as a pass and the absence of violations is read as quality.

**Acceptance:**
- Given every violation code `ChatEvalScoring` can emit, then a fixture exists that
  makes exactly that code appear.
- Given a scorer whose pattern is broken, when the suite runs, then a test fails and
  names it.
- Given a new scorer added without a fixture, then a coverage test fails listing the
  uncovered code.

### R2. Route coverage is asserted, not merely dumped (`REQ-HAR-002`)

Every scenario declares the `TurnType` and `ReplyChannel` it is expected to reach;
the run aggregates a confusion matrix and reports per-type counts. A turn type whose
count collapses is then a visible result rather than a silence.

Extend `DiagTurnRouting` and `PromptSweepRouting` rather than building a parallel
sweep — both already enumerate routing decisions and write reports.

This is the instrument `047` R1 needs: ungating the follow-up branch moves traffic
for every typed user, and the matrix is what makes that migration legible before and
after.

**Acceptance:**
- Given the scenario set, when a run completes, then it reports a `TurnType` ×
  `ReplyChannel` matrix and the observed rate of every `TurnType`.
- Given a `TurnType` observed at a rate of zero, then the run reports it explicitly
  rather than omitting the row.
- Given `047` R1 landing, then the matrix shows the before/after `followup` and
  `thread` rates from two warehoused runs.

### R3. Counterfactual world pairs (`REQ-HAR-003`)

Add paired worlds that differ in exactly one property, with the ground truth attached:

- entity present / entity absent
- a fact stated once / the same fact contradicted later (**truth decay** — "I left
  Acme in March, joined Northstar in June; where do I work?")
- supporting evidence recent / old
- one supporting entry / five near-duplicates

Contrast is the diagnostic, not volume: the entire fabrication finding came from two
worlds differing in one property. State the arithmetic in the spec so future sessions
do not re-propose scale: at the measured 2.06s p50 **serial** generation (finding 6),
300 pairs is roughly 20 minutes, 100k samples is roughly 2.4 days, and 1M is roughly
24 days. Designs premised on six-figure sample counts are not executable here, and
mocking the generator to reach them would test the scaffolding rather than the model
— none of the defects in `046` or `047` would have been detected that way.

Build on `ChatEvalCorpus` (`coldStartCorpus`, `personaCorpus`,
`deterministicUUID(for:)`) rather than a second fixture loader.

**Acceptance:**
- Given a pair, when both halves run, then the only variable between them is the
  declared property.
- Given a truth-decay pair, then the expected answer is the latest supported state
  and the superseded state is recorded as a forbidden claim.
- Given the full pair set, when run serially, then it completes within a single
  working session and the wall clock is reported.

### R4. A failure corpus that outlives the run (`REQ-HAR-004`)

Any failing generation is promotable to a checked-in case carrying its world, the
turn that produced it, the expectation and the observed violation. Once fixed, that
case is a regression test.

**Acceptance:**
- Given a failing row in `.eval-runs/`, when promoted, then a checked-in case
  reproduces it without the original run artifact.
- Given the corpus, when the suite runs, then every case is exercised and a
  re-broken defect fails by name.

### R5. Long-form capture becomes a standing harness (`REQ-HAR-005`)

Fold `ConversationSimulation` (branch `convo-sim-harness`, commits `e4d1621`,
`ad59c95`) into the eval corpus, preserving the two properties it needed to produce
usable data:

1. The **simulator's own** guardrail must not truncate a conversation. When the
   device model refuses to write the simulated person's turn, retry on a safer move
   and then fall back to a scripted line — a harness artefact must never be recorded
   as a short conversation.
2. A **designed refusal** (`guardrailRefusal`, `crisisResource`, `safetyRefusal`) is
   the app behaving as specified. Record it in place with the bubble's own copy and
   continue; only undesigned failures may end a run.

Keep the DEBUG-only `evalRawGenerate` seam on
`FoundationModelsIntelligenceService.swift` — the single module permitted to import
`FoundationModels` (`REQ-INT-001`).

**Required correction:** `ConversationSimulation.swift:191` classifies without
`lastAssistantAskedQuestion`, reproducing `047` finding 1 inside the harness. Update
it alongside `047` R1, or a re-run will not show that fix.

**Acceptance:**
- Given a run where the simulator's guardrail refuses a person's turn, then the
  conversation still reaches its planned length.
- Given a run where the app issues a designed refusal, then the conversation
  continues and the refusal is recorded with `designed_refusal: true`.
- Given `047` R1, then the harness call site passes the same conversation-state
  value the production call sites do.
- Given any run, then every message is checkpointed as it is produced, so an
  interrupted run loses at most one message.

### R6. Reporting and the arming procedure (`REQ-HAR-006`)

Metrics land in the `043` warehouse under an existing `kind`; no new kind is minted.
Thresholds are armed only after **two** warehoused runs, and the arming PR quotes
both. If a rule here becomes machine-checkable outside the model, add a named job to
`spec-gates.yml` following the existing convention,
`"<what it checks> (spec NNN Rn / REQ-XXX-nnn)"`.

**Acceptance:**
- Given a completed run, then its metrics import via `scripts/eval/import_run.sh`
  with `--prompt-version` and `--model` populated, satisfying `022` R1's discard rule.
- Given a proposed threshold, then the PR cites two warehoused runs; a threshold
  proposed from one run is rejected.

## Out of Scope

- **Worker pools and parallel execution.** `ModelRuntimeGate` serialises generation
  (finding 6); a pool over a mutex buys nothing, and the evaluators it could
  parallelise run in microseconds.
- **Privacy evaluators at this layer.** Chat is on-device, the server chat endpoints
  were retired, and `Fixtures/` is synthetic and already CI-validated by
  `validate_corpus.py`, so no eval scenario exercises a journal-bearing network path.
  A check that always passes teaches nothing; network-boundary testing belongs beside
  `OfflineResilienceTests`, not here.
- **Numeric release gates set before measurement** — contradicts
  `technology/04-evaluations.md` and this spec's own R6.
- **A synthetic world *generator*.** R3 adds authored pairs with ground truth; a
  generative population is not justified by the throughput in finding 6.
- App behaviour, which is `046` and `047`.

## Tasks

- [ ] 1. Add pattern-compile assertions and one positive fixture per violation code;
      add the coverage test that fails on an uncovered code. (R1)
- [ ] 2. Add expected `TurnType` / `ReplyChannel` to scenarios; emit the confusion
      matrix and per-type rates, including zero rows. (R2)
- [ ] 3. Author the counterfactual pairs with ground truth and forbidden claims;
      report wall clock. (R3)
- [ ] 4. Add the failure corpus and its promotion path. (R4)
- [ ] 5. Fold `ConversationSimulation` in, preserving both properties; fix the
      classifier call site alongside `047` R1. (R5)
- [ ] 6. Wire reporting into the `043` warehouse; document the arming procedure. (R6)
- [ ] 7. Register in `specs/README.md` and `ROADMAP.md`. (—)

## Verification

- [ ] `xcodebuild test -only-testing:withMementoTests/ChatEvalScoringTests` — every
      violation code has a firing fixture; a deliberately broken pattern fails by name.
- [ ] Route-coverage report lists every `TurnType` with its observed rate, zeros
      included.
- [ ] The counterfactual pair set completes in one session; wall clock recorded in
      the run artifact.
- [ ] A promoted failure case reproduces without the original `.eval-runs/` artifact.
- [ ] A long-form run where the simulator is refused still reaches planned length;
      a run containing designed refusals reaches planned length.
- [ ] `scripts/eval/import_run.sh` accepts the run with prompt version and model set.
- [ ] `scripts/ci/check_single_intelligence_importer.sh` still reports exactly 1
      after R5 (the `evalRawGenerate` seam is in the permitted module, under `#if DEBUG`).
- [ ] The default merge lane is unaffected: without its opt-in environment flag the
      long-form suite skips, and `-skip-testing:withMementoUITests` behaves as before.

## Regression Guards

- **`REQ-INT-001` / P3** — exactly one module imports `FoundationModels`. R5's
  `evalRawGenerate` lives in that module and is compiled out of Release; verify the
  symbol is absent from a Release binary.
- **Spec 022 R1** — harnesses stay local and credential-free; a run that cannot name
  its prompt version and model is discarded.
- **Spec 043** — run identity and origin labeling; no new `kind` is minted.
- **`technology/04-evaluations.md`** — measure first, threshold after. R6 is the
  procedural form of that rule.
- **CONSTITUTION §4 rule 3** — content-free logs. Run artifacts carry synthetic
  fixture content only; nothing here may record real journal text.
- **CONSTITUTION §4 rule 6** — new behaviour ships with tests; a scorer without a
  fixture is now a build failure, not a review comment.
