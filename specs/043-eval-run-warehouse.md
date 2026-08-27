---
id: 043
title: Eval Run Warehouse and Origin Labeling
tier: P2
status: in-progress (2026-08-27)
effort: 2 sessions
depends_on: [022, 041]
findings:
  - eval-runs-have-no-identity
  - eval-artifacts-overwrite-each-other
  - real-and-synthetic-feedback-indistinguishable
  - articles-have-no-ingest-path
source_refs: [REQ-EVAL-001, REQ-EVAL-005, REQ-PRIV-001]
tech_refs: [technology/04-evaluations.md]
---

# 043 — Eval Run Warehouse and Origin Labeling

**Traceability:** spec [022](022-evaluation-and-quality-study.md) owns the eval
harness and its five gates; this spec owns the *identity and storage* of what
those harnesses produce. Spec [041](041-in-chat-answer-feedback.md) owns the
on-device feedback row; this spec adds the label that says where a stored
judgment came from. Spec [042](042-feedback-telemetry-supabase.md) owns real
device telemetry in the `feedback` schema and is untouched by this work — see
Out of Scope.

## Why

Spec 022 R1 says *"every run records `promptVersion` and `modelIdentifier`… A
run that cannot say which prompt on which model produced its numbers is
discarded."* No artifact in `.eval-runs/` records either a `modelIdentifier` or
a run id, so by 022's own rule every measurement taken so far — including the
1,000-generation sweep published in `docs/THOUSAND_PROMPT_SWEEP.md` — is
formally unciteable. Runs are grouped only by fixed filename, so the second run
overwrites the first.

Separately, feedback rows carry no indication of whether a human or a model
produced them. As AI-authored critique starts arriving in volume, a single
unlabelled table makes every quality number a mixture of real and synthetic
signal with no way to separate them after the fact.

Blocks Gate 3 (production quality): a quality bar you cannot cite a run for is
not a bar.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | No run identity in any artifact | `grep -oiE '"(modelIdentifier\|runId\|gitSha\|startedAt\|device)"'` over `.eval-runs/results.json`, `sweep/sweep-0.jsonl`, `retrieval-recall.json` → **no matches** | P1 |
| 2 | Runs overwrite each other | `ChatEvalGate` writes fixed `.eval-runs/report.md` + `results.json`; `results-baseline.json` / `results-after.json` exist only as manual `cp` | P1 |
| 3 | `modelIdentifier` is available but never recorded | `IntelligenceService.swift:101` `let modelIdentifier: String` (non-optional); `MementoPromptSweep.Row` has no such field | P1 |
| 4 | One run mixes prompt versions | every shard contains both `ask@15` and `chat-light@4` (spec 039 channel routing picks per turn) — so run-level pinning is insufficient | P1 |
| 5 | 10 sweep rows carry an empty `promptVersion` | all 10 are `error: guardrailRefusal`, `chars: 0` — no generation happened | P2 |
| 6 | Feedback rows cannot say what produced them | `public.answer_feedback` had no origin column before this spec | P1 |
| 7 | `import_answer_feedback` had no `search_path` | referenced `answer_feedback` unqualified; becomes a wrong-table write the moment spec 042 creates `feedback.answer_feedback` | P2 |
| 8 | `answer_feedback.id` had no default | blocked any server-side insert (article promotion) | P2 |

## Requirements

### R1. Every stored row belongs to an identified run

`eval.run` carries `label` (unique), `kind`, `prompt_version`,
`model_identifier`, `git_sha`, `corpus_id`, `provenance`, `operator_kind`, and
timestamps. `harness_runs_are_attributable` enforces 022 R1 as a CHECK for the
model-running kinds (`harness_sweep`, `harness_gate`, `harness_agentic`);
`harness_routing` and `harness_retrieval` are exempt because no generation
occurs. `provenance = 'reconstructed'` marks a run whose attribution was
backfilled rather than captured.

**Acceptance:** inserting a `harness_sweep` run without `model_identifier`
fails. A run label cannot be reused.

### R2. Attribution is per-generation, not per-run

`eval.generation.prompt_version` / `model_identifier` are required when
`outcome = 'ok'` and exempt otherwise, because a guardrail refusal produced no
generation to attribute. `v_run_summary.distinct_prompt_versions` surfaces when
a run's own label is not a fact.

**Acceptance:** an `ok` generation without a prompt version fails; an `error`
generation without one succeeds. Importing the existing sweep yields
`distinct_prompt_versions = 2`.

### R3. Origin is stated, never defaulted

`public.answer_feedback.origin` is `NOT NULL` **with no default**, over five
values: `device_human`, `analyst_human`, `harness_llm_judge`,
`harness_machine`, `synthetic_seed`. `run_id` is `NOT NULL`, so every judgment
belongs to a session. `eval_rows_are_attributable` requires prompt and model on
every non-device row.

**Acceptance:** an insert omitting `origin` fails rather than defaulting to
real. `answer_feedback_queue` and `v_real_feedback` return device rows only.

### R4. Generations are stored apart from judgments

`eval.generation` holds the artifact under test; `answer_feedback` holds
verdicts about it, joined by `generation_id`. Rationale: `source` is NOT NULL
and mirrors Swift `rawValue`s exactly with no honest eval value; `category`
means two disjoint things across the two domains; a sweep is 1,000 rows against
single-digit weekly device feedback; and a generation is immutable history
while a feedback row is mutable current state.

**Acceptance:** "every judgment of this generation, human and machine" is a
single join. `v_run_quality_by_category` and `v_real_quality_by_category` never
mix the two category vocabularies.

### R5. Articles land raw and are promoted only after review

`eval.article` stores pasted content verbatim, deduplicated on `raw_sha256`.
`eval.article_row` holds candidate judgments with an `approved` tri-state.
`eval.promote_article` raises rather than proceeds when the article is not
approved, when any row is unreviewed, or when an approved row has no generation
to attach to.

**Acceptance:** promoting an unapproved article raises. Re-pasting an identical
article is a no-op. No unreviewed row ever reaches `answer_feedback`.

### R6. Closed by default

RLS on every `eval` table with zero policies; `security_invoker = on` on every
view; `anon`/`authenticated` revoked on tables, functions, and schema usage;
default privileges revoked so future objects inherit the posture.

**Acceptance:** as `anon`, selecting any `eval` table or view is denied. Restoring
a view grant inside a transaction still denies, via `security_invoker`.

### R7. Import is out-of-band

Harnesses keep writing `.eval-runs/` exactly as today. Ingestion is a separate
CLI step over artifacts already on disk. No harness acquires a credential, and
no CI gate depends on the database.

**Acceptance:** a clean checkout with networking disabled still runs every
harness and every gate.

## Out of Scope

- **Real device telemetry** — spec 042 owns `feedback.*`, its consent tiers, and
  the app's network client. This spec touches no app-target code. The bridge
  from 042's landing zone into this warehouse is written only when 042 ships.
- **Stamping run identity inside the Swift harnesses** — required to reach
  `provenance = 'captured'`, tracked as R2 of a follow-up. Until then imports
  carry attribution from CLI flags and are marked `reconstructed`.
- **LLM-as-judge scoring** — 022 R4's decision block still reads OPEN. This spec
  stores a judge's verdict; it does not create one.

## Tasks

- [x] 1. `eval` schema, run identity, attribution CHECKs (R1)
- [x] 2. `eval.generation`, citations, violations, code reference table (R2, R4)
- [x] 3. `origin` + `run_id` on `answer_feedback`; relax `source`/`message_id`;
      rewrite `import_answer_feedback` with `search_path` (R3, plus evidence 7/8)
- [x] 4. `eval.article`, `eval.article_row`, `eval.promote_article` (R5)
- [x] 5. Metric views + access hardening (R4, R6)
- [x] 6. `scripts/eval/import_run.sh` + ingest functions (R7)
- [x] 7. Import the existing sweep and the baseline/after gate pair as
      `reconstructed` runs; confirm the regression views reproduce the manual
      comparison
- [x] 8. Amend 022 R1, 041, 042; register in README and ROADMAP

## Verification

- [ ] `supabase db reset` replays all migrations from zero
- [ ] `insert into public.answer_feedback (…)` omitting `origin` → error
- [ ] `insert into eval.run (kind => 'harness_sweep', …)` without
      `model_identifier` → error
- [ ] a second `is_baseline` run of the same `(kind, corpus_id)` → error
- [ ] `set role anon; select * from eval.generation;` → permission denied
- [ ] import `.eval-runs/sweep/sweep-*.jsonl` (1,000 rows) →
      `v_run_summary.generations = 1000`, `failures = 10`,
      `distinct_prompt_versions = 2`
- [ ] import `results-baseline.json` / `results-after.json` (100 rows each),
      mark the first baseline → `v_regression` returns one row and
      `v_regression_by_item` classifies every item
- [ ] re-run both imports → row counts unchanged (idempotent)
- [ ] `supabase db push`; `supabase migration list` agrees local and remote

## Regression Guards

- **REQ-PRIV-001** — this schema stores synthetic fixture data and
  developer/LLM critique only. `eval.is_fixture_id_array` structurally rejects
  journal UUIDs in citation columns. Real user content reaching this database
  is spec 042's decision to make, under its consent model, not this spec's.
- **Spec 041 R5/R6** — the on-device store and its one-row-per-`messageID` rule
  are unchanged. `message_id` uniqueness is preserved as a partial index; only
  its NOT NULL is relaxed, and `device_rows_keep_041_shape` holds device rows to
  the original contract.
- **Spec 022 R1** — the local-only clause is narrowed, not removed: the run
  stays credential-free and offline-capable. See the dated amendment in 022.
