-- Spec 043 — generations and violations.
--
-- A generation is NOT a feedback row. answer_feedback records a judgment
-- ("this answer was bad, and why"); a generation records the artifact being
-- judged ("this prompt produced this text in this many seconds"). They are
-- kept apart for four reasons, any one sufficient:
--
--   1. answer_feedback.source is NOT NULL and mirrors Swift rawValues exactly.
--      A sweep generation was neither a thumbsUp, thumbsDown, nor a report,
--      and adding an 'evalHarness' case would break the mirror invariant that
--      both this migration set and spec 042 rely on.
--   2. "category" means two disjoint things. Feedback: wrongRecall/tone/...
--      Sweep: mood/work/temporal/... One column would make "quality by
--      category" silently return a mixture of two vocabularies.
--   3. One sweep is 1,000 rows; real device feedback is single digits a week.
--   4. answer_feedback is mutable current-state keyed by message_id;
--      a generation is an immutable historical fact keyed by (run, item, rep).
--
-- The join answer_feedback.generation_id -> eval.generation.id is what makes
-- "every judgment of this reply, human and machine" a one-line query.

create type eval.generation_outcome as enum ('ok', 'error', 'empty', 'skipped');

-- REQ-PRIV-001 guard, structural. Eval citations are fixture string ids
-- ('e-2026-03-08-1'), never journal UUIDs. Immutable, so it is CHECK-legal.
create function eval.is_fixture_id_array(ids text[]) returns boolean
language sql immutable as $$
    select coalesce(bool_and(x ~ '^e-\d{4}-\d{2}-\d{2}-\d+$'), true)
    from unnest(coalesce(ids, '{}')) x
$$;

create table eval.generation (
    id                  uuid primary key default gen_random_uuid(),
    run_id              uuid not null references eval.run(id) on delete cascade,

    -- The harness's own identifier as text, so one table serves all of them:
    -- sweep index, gate scenario, gold question id, probe id.
    item_key            text not null,
    rep                 int not null default 1,

    -- The harness's OWN vocabulary (mood/work/temporal/...). Deliberately not
    -- answer_feedback_category: same word, different domain.
    prompt_category     text,
    scenario            text,
    corpus              text,
    question            text not null,
    has_history         boolean not null default false,

    body                text not null default '',
    chars               int not null default 0,
    words               int not null default 0,
    seconds             double precision check (seconds is null or seconds >= 0),
    outcome             eval.generation_outcome not null default 'ok',
    error               text,

    -- Per-row, because a single run mixes versions (verified). Required only
    -- for generations that actually succeeded: the 10 guardrailRefusal rows
    -- in the existing sweep have an empty promptVersion precisely because no
    -- generation happened. Demanding attribution for a refusal would reject
    -- real data to satisfy a rule that does not apply to it.
    prompt_version      text,
    model_identifier    text,
    zone                text,
    degraded            boolean not null default false,

    -- Routing context, joinable from PromptSweepRouting output.
    channel             text,
    turn_kind           text,
    retrieval_mode      text,
    token_cap           int,

    citation_fixture_ids   text[] not null default '{}'
                           check (eval.is_fixture_id_array(citation_fixture_ids)),
    citation_count         int not null default 0,
    expected_fixture_ids   text[]
                           check (eval.is_fixture_id_array(expected_fixture_ids)),
    match_rule             text check (match_rule in ('all', 'any', 'none')),
    retrieval_outcome      text,
    precision              double precision,
    recall                 double precision,

    passed                 boolean,
    gating_violation_count int not null default 0,
    created_at             timestamptz not null default now(),

    constraint generation_item_unique unique (run_id, item_key, rep),

    -- Spec 022 R1 at row grain: a SUCCESSFUL generation must say which prompt
    -- on which model produced it. Failures are exempt.
    constraint ok_generations_are_attributable
        check (
            outcome <> 'ok'
            or (prompt_version is not null and prompt_version <> ''
                and model_identifier is not null and model_identifier <> '')
        )
);

create index gen_run_category on eval.generation (run_id, prompt_category);
create index gen_run_item     on eval.generation (run_id, item_key);
create index gen_prompt_model on eval.generation (prompt_version, model_identifier);
create index gen_uncited      on eval.generation (run_id) where citation_count = 0;

-- Citation excerpts live in a child table. They are synthetic fixture text,
-- so storing them is safe, and they are the raw material for grounding review.
create table eval.generation_citation (
    generation_id uuid not null references eval.generation(id) on delete cascade,
    ord           int not null,
    fixture_id    text not null check (fixture_id ~ '^e-\d{4}-\d{2}-\d{2}-\d+$'),
    entry_date    timestamptz,
    excerpt       text,
    primary key (generation_id, ord)
);

create table eval.violation (
    generation_id uuid not null references eval.generation(id) on delete cascade,
    ord           int not null,
    code          text not null,
    -- leak | rule | hall | gold | gen — the ChatEvalScoring families, free.
    family        text generated always as (split_part(code, '.', 1)) stored,
    detail        text,
    -- ChatEvalScoring.gating() is everything except gen.*: gen.hitTokenCap is
    -- a budget observation, not a quality fault. Folding it into the
    -- regression metric would make longer answers look like regressions.
    gating        boolean not null default false,
    primary key (generation_id, ord)
);

create index violation_code_idx   on eval.violation (code);
create index violation_family on eval.violation (family, gating);

-- Vocabulary as reference data, NOT as a foreign key. A new code in
-- ChatEvalScoring.swift must not block ingest — that would put friction on
-- exactly the iteration loop this exists to make cheap — but it must not
-- vanish silently either, hence the unknown-codes view.
create table eval.violation_code (
    code        text primary key,
    family      text not null,
    gating      boolean not null,
    description text,
    added_at    timestamptz not null default now()
);

create view eval.v_unknown_violation_codes with (security_invoker = on) as
select v.code, count(*) as n, min(r.label) as first_seen_in_run
from eval.violation v
join eval.generation g on g.id = v.generation_id
join eval.run r on r.id = g.run_id
left join eval.violation_code c on c.code = v.code
where c.code is null
group by v.code
order by n desc;
