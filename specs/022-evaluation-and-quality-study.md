---
id: 022
title: Evaluation and Quality Study
tier: P2
status: not-started
effort: 2 sessions
depends_on: [013, 016, 017, 019]
findings: []
source_refs: [REQ-EVAL-001, REQ-EVAL-002, REQ-EVAL-003, REQ-EVAL-004, REQ-EVAL-005]
tech_refs: [technology/04-evaluations.md]
---

# 022 — Evaluation and Quality Study

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§13 "Evaluation and the quality study" in full.

## Why

The 30-day AI quality study originally designed for 1.3 would validate an
architecture that no longer exists by the time it could run — it is paused and
re-baselined against the 2.0 metrics table, keeping its cohort/survey structure
intact (three cohorts, daily micro-surveys, weekly check-ins, end-of-study survey,
exit interviews) but adding a forced-degradation cohort (`REQ-EVAL-003`) that
could be a genuinely load-bearing finding: if Z0-only satisfaction is close to
PCC-baseline, the absolute-privacy positioning claim in the source doc's §1.3
should be revisited *before* launch, not after.

## Technology References

- `specs/reference/technology/04-evaluations.md` — primary: `import
  Evaluations` (`ModelSampleProtocol`, `TrajectoryExpectation`,
  `ArrayLoader`, `evaluation.run()`), the five quality-gate thresholds, and
  the Xcode 27 Foundation Models instrument used instead of custom timing
  infrastructure.

## Current State (evidence)

No golden-set evaluation harness, no `SchemaMigrationPlan`-style eval fixture, and
no forced-degradation study design exist in this repo — greenfield. Depends on
spec 013's fixture corpus (reused here, not rebuilt) and specs 016/017/019
actually existing to have something to evaluate.

## Requirements

- [ ] TODO (derive from source doc §13, per its §17 checklist): golden-set
  evaluation harness contract (`REQ-PRM-005`, spec 017 — this spec is the primary
  *consumer*, confirm the interface matches what's needed here) — **built on
  Apple's `Evaluations` framework, not hand-rolled** (`technology/04`: iOS 27
  ships `ModelSampleProtocol` with `expectedIdentifiers` for automatic recall@k,
  `TrajectoryExpectation` for did-it-actually-search assertions, `ArrayLoader`,
  and Swift Testing integration — the source doc predates this framework's
  availability, and its "runs locally, ships with the repo, requires no service"
  constraint is exactly what the framework provides); structure the suite as the
  **five CI gates** from `technology/04` §5, which subsume and extend
  `REQ-EVAL-002`'s metrics table:
  1. *Retrieval* — recall@5 ≥ 0.85, plus **search-tool-called on 100% of Ask
     queries** via `TrajectoryExpectation` (the mechanical enforcement of
     `REQ-SUR-003`: an answer synthesized from the model's priors about the
     user's own life is a fabrication, and this catches it on every prompt
     change);
  2. *Grounding* — citation accuracy ≥ 95%, ungrounded-claim rate ≤ 2%;
     ID-exists-and-was-retrieved is automatable, claim-entailment needs a judge
     — **decision to record**: an on-device LLM-as-judge (Z0, costs nothing,
     leaks nothing) with human spot-checks is the recommended answer;
  3. *Persona* — no-advice ≥ 98%, no-diagnosis 100%, crisis-routing 100%,
     against the adversarial prompts baked into spec 013's fixture corpus;
  4. *Restraint* — `hasNothingToSay` fires on sparse periods ≥ 90%, observation
     suppressed on ordinary entries ≥ 60%, plus **guardrail refusal rate**
     logged over the emotionally-heavy fixture content (if it exceeds a few
     percent, the prompt framing is provoking it — `technology/01` §11);
  5. *Degradation* — Z0-fallback satisfaction ≥ 60% of Z1 baseline
     (blind-rated), Z0 output passes the `SpeakabilityLinter` 100%;
  p50 entry-reflection latency < 2s stays automatable via spec 019's
  instrumentation; forced-degradation cohort design (`REQ-EVAL-003`); Xcode 27
  Foundation Models instrument wiring for tool-call loops / time-to-first-token
  / latency attribution (`REQ-EVAL-004`) — do not build custom timing
  infrastructure, use the instrument; quota/availability state testing via
  Xcode's **"Simulate Apple Foundation Models Availability"** debug option
  (✅ verified) — every Z1 surface gets tests for available / approaching-limit
  / limit-reached / unavailable, plus all four capability tiers from source doc
  §4.1; the manual arm (helpfulness, willingness-to-pay, interviews) stays
  survey-based per `REQ-EVAL-005`; investigate the Sample Generation APIs (V14)
  to expand the hand-authored 40-query gold set toward ~200 queries.

## Out of Scope

- Building the golden-set harness's underlying fixture corpus — spec 013 already
  owns that; this spec reuses it.
- Any in-app analytics SDK — explicitly excluded by `REQ-EVAL-005`; all telemetry
  is manual survey/interview collection.
- Acting on study findings (e.g. revisiting the §1.3 positioning claim if the
  forced-degradation cohort's result warrants it) — that's a product decision for
  whoever reads this study's output, not something this spec resolves in advance.

## Tasks
- [ ] 1. Build the golden-set evaluation harness on the `Evaluations` framework
      (fixture corpus + fixed question set + prompt-version-under-test +
      disk-captured output for manual review), per `REQ-PRM-005`; confirm the
      `SpotlightSearchTool` registered tool name for trajectory expectations
      (V12 — Apple's sample uses `"searchSpotlight"`).
- [ ] 2. Implement the five CI gates as Swift Testing suites; wire recall@5 to
      spec 016's gate and p50 latency to spec 019's instrumentation rather than
      rebuilding them.
- [ ] 3. Record the LLM-as-judge decision for citation entailment (Gate 2) and
      implement it with human spot-checks if adopted.
- [ ] 4. Design the three-cohort study structure + forced-degradation cohort
      (`REQ-EVAL-001`, `REQ-EVAL-003`) — if Z0-only satisfaction lands close to
      the Z1 baseline, escalate before launch: the §1.3 positioning claim should
      be revisited while marketing copy is still unlocked.
- [ ] 5. Wire the Xcode 27 Foundation Models instrument (`REQ-EVAL-004`) and
      the "Simulate Apple Foundation Models Availability" debug option into the
      degradation/tier test suites.
- [ ] 6. Design the manual survey/interview instruments for the non-automatable
      metrics in `REQ-EVAL-002` (`REQ-EVAL-005`).
- [ ] 7. Investigate Sample Generation APIs (V14) for gold-set expansion; adopt
      if the signature supports seeded expansion from the hand-authored set.

## Verification
- [ ] TODO — derive concrete test/review steps once Requirements are written;
      must confirm the harness runs locally with no external service dependency
      per the source doc's explicit requirement.

## Regression Guards
None — this spec adds measurement infrastructure, it doesn't touch product code
paths that could regress a `CONSTITUTION.md` guarantee. Its own output (the
study results) may trigger regression guards in *other* specs if findings warrant
revisiting a decision — that's handled there, not here.
