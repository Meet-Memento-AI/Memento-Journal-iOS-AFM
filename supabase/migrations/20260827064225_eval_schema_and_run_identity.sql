-- Spec 043 — eval run identity.
--
-- The gap this closes: no eval artifact on disk carries a run id, a model
-- identifier, a git sha, or a timestamp. Runs are grouped by fixed filename,
-- so a second run overwrites the first — .eval-runs/results-baseline.json and
-- results-after.json exist only because someone ran `cp` by hand.
--
-- Spec 022 R1: "every run records promptVersion and modelIdentifier; a run
-- that cannot say which prompt on which model produced its numbers is
-- discarded." That rule is enforced here as a constraint rather than a
-- convention.
--
-- This schema holds SYNTHETIC fixture data and developer-authored critique
-- only. Spec 042 owns the "feedback" schema for real device telemetry; the
-- two never merge. See specs/043 for the boundary.

create schema if not exists eval;

comment on schema eval is
    'Spec 043 eval warehouse. Synthetic fixture data and analyst/LLM critique '
    'only, never user journal content. Service_role/psql access only. '
    'Spec 042 owns the "feedback" schema; this is the curated side.';

create type eval.run_kind as enum (
    'harness_sweep',          -- MementoPromptSweep
    'harness_gate',           -- ChatEvalGate
    'harness_agentic',        -- AgenticEval
    'harness_retrieval',      -- RetrievalRecallDiag (no generation)
    'harness_routing',        -- PromptSweepRouting (no model at all)
    'manual_device_session',  -- a real device export, imported by hand
    'article_batch'           -- a pasted AI-authored critique
);

create type eval.run_status as enum ('open', 'complete', 'discarded');

-- 'reconstructed' is how a run whose model was never stamped at runtime gets
-- imported honestly. The 1,000-generation sweep in docs/THOUSAND_PROMPT_SWEEP.md
-- names its model only in prose ("iOS 27 simulator, on-device Foundation
-- model"), so it comes in reconstructed and is never mistaken for a clean run.
create type eval.provenance as enum ('captured', 'reconstructed');

-- Who drove the run. Makes the operator itself a measurable variable, which
-- matters when eval sessions are driven by fresh Claude Code sessions.
create type eval.operator_kind as enum ('human', 'claude_code', 'ci');

create table eval.run (
    id                  uuid primary key default gen_random_uuid(),

    -- The handle a fresh session types. UNIQUE is the fix for the overwrite
    -- bug: a re-run under an existing label fails instead of clobbering.
    label               text not null unique,
    kind                eval.run_kind not null,
    status              eval.run_status not null default 'open',
    provenance          eval.provenance not null default 'captured',

    -- Nullable at run level on purpose. A sweep mixes prompt versions within
    -- one run (verified: ask@15 and chat-light@4 in every shard), so the
    -- authoritative value lives on eval.generation. The run-level value is
    -- "the version under test". The CHECK below still enforces 022 R1 for
    -- the harness kinds where it means something.
    prompt_version      text,
    model_identifier    text,

    git_sha             text,
    git_branch          text,
    git_dirty           boolean not null default false,
    harness             text,
    corpus_id           text not null default 'fixtures@2026-07-23',
    os_version          text,
    device_model        text,

    -- is_baseline answers "what do I compare against now".
    -- baseline_run_id freezes "what was this actually compared against then",
    -- so moving the baseline does not silently rewrite past comparisons.
    is_baseline         boolean not null default false,
    baseline_run_id     uuid references eval.run(id),

    operator_kind       eval.operator_kind not null default 'human',
    operator_ref        text,

    started_at          timestamptz not null default now(),
    finished_at         timestamptz,
    notes               text,
    imported_at         timestamptz not null default now(),

    constraint run_finished_after_start
        check (finished_at is null or finished_at >= started_at),

    constraint complete_runs_are_closed
        check (status <> 'complete' or finished_at is not null),

    -- Spec 022 R1, structural. Model-running harnesses must name prompt and
    -- model. Exempt: harness_routing (pure Swift, no model), harness_retrieval
    -- (retrieval only, no generation), and the two import kinds, whose rows
    -- carry their own per-row attribution instead.
    constraint harness_runs_are_attributable
        check (
            kind not in ('harness_sweep', 'harness_gate', 'harness_agentic')
            or (prompt_version is not null and prompt_version <> ''
                and model_identifier is not null and model_identifier <> '')
        )
);

-- Exactly one live baseline per (kind, corpus). Comparing runs across corpora
-- is not a regression, it is a category error.
create unique index run_one_baseline
    on eval.run (kind, corpus_id) where is_baseline;

create index run_kind_started on eval.run (kind, started_at desc);

comment on column eval.run.prompt_version is
    'The version under test. Authoritative per-row value is on eval.generation '
    '— a single run mixes prompt versions via spec 039 channel routing.';
