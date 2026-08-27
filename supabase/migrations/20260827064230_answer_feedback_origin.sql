-- Spec 043 — origin labeling on the judgment table.
--
-- One table holds every judgment about an answer, real or synthetic, with an
-- origin label — so real and AI-authored critique sit side by side and are
-- directly comparable. The cost of one table is that a metric query which
-- forgets to filter silently mixes them; the guards below are what make that
-- filter hard to forget.

create type eval.feedback_origin as enum (
    'device_human',       -- a real person using the shipping app
    'analyst_human',      -- the developer hand-reviewing eval output
    'harness_llm_judge',  -- an LLM authored the critique (the pasted articles)
    'harness_machine',    -- a ChatEvalScoring violation promoted to a judgment
    'synthetic_seed'      -- demo/test rows that must NEVER count
);

-- 'analyst_human' is why this is five values and not two: a developer judging
-- a synthetic reply is a REAL human judgment on SYNTHETIC input, and it is the
-- highest-value data here. Collapsing it into "synthetic" would lose that.

alter table public.answer_feedback
    add column origin        eval.feedback_origin,
    add column run_id        uuid references eval.run(id) on delete restrict,
    add column generation_id uuid references eval.generation(id) on delete set null,
    add column judge_model   text,
    add column confidence    smallint check (confidence between 1 and 5),
    add column article_id    uuid;   -- FK added with eval.article

-- Backfill defensively. Both local and cloud are empty today, but a migration
-- should not assume that.
do $$
declare v_run uuid;
begin
    if exists (select 1 from public.answer_feedback) then
        insert into eval.run (label, kind, status, provenance, corpus_id,
                              notes, started_at, finished_at)
        values ('device-import-backfill', 'manual_device_session', 'complete',
                'reconstructed', 'live-user-journal',
                'Synthesized by migration 20260827064230 for rows that predate '
                'run identity.', now(), now())
        returning id into v_run;

        update public.answer_feedback
           set origin = 'device_human', run_id = v_run
         where origin is null;
    end if;
end $$;

-- NOT NULL with NO DEFAULT, deliberately. A default of 'device_human' reads
-- as friendlier and is strictly worse: the failure it creates (eval rows
-- silently counted as real users) is invisible and permanent, while the
-- failure it prevents (an error on a forgetful INSERT) costs ten seconds.
alter table public.answer_feedback
    alter column origin  set not null,
    alter column run_id  set not null,
    -- F4: no default meant server-side inserts (article promotion, LLM
    -- judgments) could not mint a row at all. Same for the timestamps: the
    -- client always supplied them, so a server-authored row was impossible.
    -- Device imports still pass all three explicitly, so nothing changes there.
    alter column id set default gen_random_uuid(),
    alter column created_at set default now(),
    alter column updated_at set default now();

-- Eval rows have no thumbs and no device message. Relax rather than invent
-- fake enum values: these enums mirror Swift rawValues exactly, and
-- 'evalHarness' has no Swift counterpart.
alter table public.answer_feedback
    alter column source drop not null,
    alter column message_id drop not null;

alter table public.answer_feedback drop constraint answer_feedback_message_id_key;

create unique index answer_feedback_message_unique
    on public.answer_feedback (message_id) where message_id is not null;

create unique index answer_feedback_generation_judge_unique
    on public.answer_feedback (generation_id, origin, coalesce(judge_model, ''))
    where generation_id is not null;

alter table public.answer_feedback
    -- Every judgment points at exactly one subject.
    add constraint judgment_has_a_subject
        check (message_id is not null or generation_id is not null),

    -- Device rows keep spec 041's shape verbatim.
    add constraint device_rows_keep_041_shape
        check (origin <> 'device_human'
               or (source is not null and message_id is not null)),

    -- Spec 022 R1 at the door: a judgment about a generated answer must say
    -- which prompt on which model produced it. Device rows are exempt because
    -- live in-session feedback genuinely has nil metadata until an app
    -- relaunch — that is a client bug to fix, not a reason to reject the row.
    add constraint eval_rows_are_attributable
        check (origin = 'device_human'
               or (prompt_version is not null and prompt_version <> ''
                   and model_identifier is not null and model_identifier <> '')),

    -- An LLM judgment must name its judge.
    add constraint llm_judgments_name_the_judge
        check (origin <> 'harness_llm_judge' or judge_model is not null);

create index answer_feedback_origin_idx on public.answer_feedback (origin, updated_at desc);
create index answer_feedback_run_idx    on public.answer_feedback (run_id);

comment on column public.answer_feedback.origin is
    'What produced this judgment. NOT NULL with no default on purpose: an '
    'insert that forgets to say fails loudly rather than defaulting to real.';

-- The triage queue becomes real-only: the filter now lives in the view, so
-- ad-hoc triage cannot accidentally surface synthetic rows.
create or replace view public.answer_feedback_queue as
select
    message_id,
    rating,
    flagged_for_review,
    category,
    note,
    user_prompt,
    assistant_reply,
    prompt_version,
    model_identifier,
    was_degraded,
    safety_presentation,
    coalesce(array_length(citation_entry_ids, 1), 0) as citation_count,
    updated_at
from public.answer_feedback
where origin = 'device_human'
  and (rating = 'negative' or flagged_for_review)
order by flagged_for_review desc, updated_at desc;

-- The two views a metric query should reach for instead of the base table.
create view public.v_real_feedback with (security_invoker = on) as
select * from public.answer_feedback where origin = 'device_human';

create view eval.v_synthetic_feedback with (security_invoker = on) as
select * from public.answer_feedback where origin <> 'device_human';

revoke all on table public.v_real_feedback    from anon, authenticated;
revoke all on table eval.v_synthetic_feedback from anon, authenticated;

-- The device import must now stamp origin and a run, so it is rewritten here.
--
-- F3 fix: the original body referenced `answer_feedback` unqualified with no
-- `set search_path`. Harmless today, but the moment spec 042 creates
-- feedback.answer_feedback, a caller whose search_path starts with `feedback`
-- would write to the wrong table. Both hazards are closed below.
-- Drop the 1-arg version first: adding a defaulted second parameter creates
-- an OVERLOAD rather than replacing it, and a 1-arg call would then be
-- ambiguous between the two. The old body also predates origin/run_id
-- being NOT NULL, so leaving it callable would guarantee a failure.
drop function if exists public.import_answer_feedback(jsonb);

create or replace function public.import_answer_feedback(
    payload jsonb,
    run_label text default null
)
returns integer
language plpgsql
set search_path = public, eval, pg_temp
as $$
declare
    affected integer;
    v_run    uuid;
    v_label  text := coalesce(
        run_label,
        'device-import-' || to_char(now(), 'YYYY-MM-DD"T"HH24MISS')
    );
begin
    -- Device runs carry no single prompt/model: live in-session feedback has
    -- nil metadata until relaunch, and one export spans many turns. The run
    -- kind is exempt from harness_runs_are_attributable for exactly that
    -- reason, so these stay NULL rather than being filled with a fake value.
    insert into eval.run (label, kind, status, provenance, corpus_id,
                          operator_kind, started_at, finished_at)
    values (v_label, 'manual_device_session', 'complete', 'reconstructed',
            'live-user-journal', 'human', now(), now())
    on conflict (label) do update set label = excluded.label
    returning id into v_run;

    insert into public.answer_feedback (
        id, message_id, session_id, rating, flagged_for_review, source,
        category, note, user_prompt, assistant_reply, citation_entry_ids,
        prompt_version, model_identifier, zone, was_degraded,
        safety_presentation, app_version, created_at, updated_at,
        origin, run_id
    )
    select
        (r ->> 'id')::uuid,
        (r ->> 'messageID')::uuid,
        (r ->> 'sessionID')::uuid,
        coalesce(r ->> 'rating', 'none')::answer_feedback_rating,
        coalesce((r ->> 'flaggedForReview')::boolean, false),
        (r ->> 'source')::answer_feedback_source,
        (r ->> 'category')::answer_feedback_category,
        r ->> 'note',
        coalesce(r ->> 'userPrompt', ''),
        coalesce(r ->> 'assistantReply', ''),
        coalesce(
            (select array_agg(v::uuid)
             from jsonb_array_elements_text(r -> 'citationEntryIDs') as v),
            '{}'::uuid[]
        ),
        r ->> 'promptVersion',
        r ->> 'modelIdentifier',
        r ->> 'zone',
        (r ->> 'wasDegraded')::boolean,
        coalesce(r ->> 'safetyPresentation', 'none')::chat_safety_presentation,
        coalesce(r ->> 'appVersion', ''),
        (r ->> 'createdAt')::timestamptz,
        (r ->> 'updatedAt')::timestamptz,
        'device_human'::eval.feedback_origin,
        v_run
    from jsonb_array_elements(payload) as r
    on conflict (message_id) where message_id is not null do update set
        session_id          = excluded.session_id,
        rating              = excluded.rating,
        flagged_for_review  = excluded.flagged_for_review,
        category            = excluded.category,
        note                = excluded.note,
        source              = excluded.source,
        user_prompt         = excluded.user_prompt,
        assistant_reply     = excluded.assistant_reply,
        citation_entry_ids  = excluded.citation_entry_ids,
        prompt_version      = excluded.prompt_version,
        model_identifier    = excluded.model_identifier,
        zone                = excluded.zone,
        was_degraded        = excluded.was_degraded,
        safety_presentation = excluded.safety_presentation,
        app_version         = excluded.app_version,
        updated_at          = excluded.updated_at,
        imported_at         = now();

    get diagnostics affected = row_count;
    return affected;
end $$;

revoke all on function public.import_answer_feedback(jsonb, text)
    from anon, authenticated;
