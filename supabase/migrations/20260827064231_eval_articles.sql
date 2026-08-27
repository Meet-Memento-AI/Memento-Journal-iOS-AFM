-- Spec 043 — article staging.
--
-- AI-authored feedback arrives as prose or structured exports, pasted over
-- time. It lands here VERBATIM first, gets parsed into candidate rows, and
-- only reaches answer_feedback after explicit approval. The review gate is the
-- point: AI-authored critique flowing straight into metrics would move the
-- numbers with nothing recording that it happened.

create type eval.article_status as enum (
    'pasted', 'parsed', 'needs_review', 'approved', 'promoted', 'rejected'
);

create type eval.article_format as enum ('prose', 'json', 'csv', 'transcript');

create table eval.article (
    id           uuid primary key default gen_random_uuid(),
    run_id       uuid not null references eval.run(id),  -- kind = 'article_batch'
    title        text,
    format       eval.article_format not null default 'prose',

    -- Verbatim, never edited or re-parsed in place. Re-pasting the same
    -- article weeks later is a no-op rather than a duplicate.
    raw_text     text not null,
    raw_sha256   text not null unique,
    raw_json     jsonb,

    source_note  text,
    author_model text,
    status       eval.article_status not null default 'pasted',
    pasted_at    timestamptz not null default now(),
    parsed_at    timestamptz,
    reviewed_at  timestamptz,
    reviewed_by  text,
    review_note  text
);

create table eval.article_row (
    id                     uuid primary key default gen_random_uuid(),
    article_id             uuid not null references eval.article(id) on delete cascade,
    ord                    int not null,

    -- The prose slice this judgment came from, kept so a promoted row can
    -- always be traced back to the sentence that produced it.
    claim                  text not null,
    proposed_category      answer_feedback_category,
    proposed_rating        answer_feedback_rating not null default 'negative',
    proposed_generation_id uuid references eval.generation(id),

    match_method           text not null default 'unmatched'
                           check (match_method in ('item_key','quote','manual','unmatched')),
    match_score            double precision,

    approved               boolean,   -- NULL = not yet reviewed
    promoted_feedback_id   uuid references public.answer_feedback(id),

    unique (article_id, ord)
);

create index article_row_pending on eval.article_row (article_id) where approved is null;

alter table public.answer_feedback
    add constraint answer_feedback_article_fk
    foreign key (article_id) references eval.article(id) on delete set null;

-- Promotion. The review step is a precondition enforced in SQL, not a
-- convention someone remembers.
create function eval.promote_article(p_article uuid)
returns integer
language plpgsql
set search_path = eval, public, pg_temp
as $$
declare
    v_status    eval.article_status;
    v_pending   int;
    v_unmatched int;
    v_n         int;
begin
    select status into v_status from eval.article where id = p_article;
    if v_status is null then
        raise exception 'no such article %', p_article;
    end if;
    if v_status <> 'approved' then
        raise exception 'article % is %, not approved', p_article, v_status;
    end if;

    select count(*) into v_pending
      from eval.article_row where article_id = p_article and approved is null;
    if v_pending > 0 then
        raise exception '% row(s) still unreviewed on article %', v_pending, p_article;
    end if;

    -- An approved row with nothing to attach to is a hard error, not a silent
    -- skip. An inner join would drop it and the returned count would not say so.
    select count(*) into v_unmatched
      from eval.article_row
     where article_id = p_article and approved and proposed_generation_id is null;
    if v_unmatched > 0 then
        raise exception
            '% approved row(s) on article % have no generation to attach to',
            v_unmatched, p_article;
    end if;

    with promoted as (
        insert into public.answer_feedback (
            origin, run_id, generation_id, article_id, judge_model,
            rating, category, note, flagged_for_review,
            user_prompt, assistant_reply,
            prompt_version, model_identifier, zone, was_degraded,
            created_at, updated_at
        )
        select
            'harness_llm_judge'::eval.feedback_origin,
            a.run_id, ar.proposed_generation_id, a.id, a.author_model,
            ar.proposed_rating, ar.proposed_category,
            left(ar.claim, 280), false,
            g.question, g.body,
            g.prompt_version, g.model_identifier, g.zone, g.degraded,
            a.pasted_at, now()
        from eval.article_row ar
        join eval.article a    on a.id = ar.article_id
        join eval.generation g on g.id = ar.proposed_generation_id
        where ar.article_id = p_article and ar.approved
        returning id
    )
    select count(*) into v_n from promoted;

    update eval.article set status = 'promoted' where id = p_article;
    return v_n;
end $$;

revoke all on function eval.promote_article(uuid) from anon, authenticated;
