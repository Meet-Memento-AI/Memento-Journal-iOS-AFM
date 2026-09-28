-- Spec 042 follow-up: citation_count on device reports (never UUIDs)
-- and source on the triage queue so Reports are filterable.

alter table public.answer_feedback
    add column if not exists citation_count integer not null default 0;

comment on column public.answer_feedback.citation_count is
    'Count of journal citations on the reported turn. UUIDs are never stored.';

create or replace function public.submit_device_feedback(payload jsonb)
returns integer
language plpgsql
security definer
set search_path = public, eval, pg_temp
as $$
declare
    affected integer := 0;
    v_run    uuid;
    v_device uuid;
    v_include boolean;
    v_source  answer_feedback_source;
    v_rating  answer_feedback_rating;
    v_category answer_feedback_category;
    v_safety  chat_safety_presentation;
    v_prompt  text;
    v_reply   text;
    v_note    text;
    v_cites   integer;
begin
    begin
        v_device := (payload->>'deviceID')::uuid;
    exception when others then
        v_device := null;
    end;
    if v_device is null then
        raise exception 'deviceID required' using errcode = '22023';
    end if;

    select id into v_run
      from eval.run
     where label = 'device-verification-live';
    if v_run is null then
        insert into eval.run (label, kind, status, provenance, corpus_id, operator_kind, started_at)
        values ('device-verification-live', 'manual_device_session', 'open',
                'captured', 'live-user-journal', 'human', now())
        returning id into v_run;
    end if;

    v_source := case payload->>'source'
        when 'thumbsUp' then 'thumbsUp'::answer_feedback_source
        when 'thumbsDown' then 'thumbsDown'::answer_feedback_source
        when 'report' then 'report'::answer_feedback_source
        else null
    end;
    if v_source is null then
        raise exception 'source required' using errcode = '22023';
    end if;

    v_rating := case coalesce(payload->>'rating', 'none')
        when 'positive' then 'positive'::answer_feedback_rating
        when 'negative' then 'negative'::answer_feedback_rating
        else 'none'::answer_feedback_rating
    end;

    v_category := case payload->>'category'
        when 'wrongRecall' then 'wrongRecall'::answer_feedback_category
        when 'madeSomethingUp' then 'madeSomethingUp'::answer_feedback_category
        when 'didntAnswer' then 'didntAnswer'::answer_feedback_category
        when 'tone' then 'tone'::answer_feedback_category
        when 'safety' then 'safety'::answer_feedback_category
        when 'other' then 'other'::answer_feedback_category
        else null
    end;

    v_safety := case payload->>'safetyPresentation'
        when 'crisisResource' then 'crisisResource'::chat_safety_presentation
        when 'hardRefuse' then 'hardRefuse'::chat_safety_presentation
        when 'emptyObservation' then 'emptyObservation'::chat_safety_presentation
        else 'none'::chat_safety_presentation
    end;

    v_include := (v_source = 'report')
                 and coalesce((payload->>'textIncluded')::boolean, false);
    v_prompt := case when v_include then coalesce(payload->>'userPrompt', '') else '' end;
    v_reply  := case when v_include then coalesce(payload->>'assistantReply', '') else '' end;
    v_note   := nullif(left(coalesce(payload->>'note', ''), 280), '');
    v_cites  := greatest(coalesce((payload->>'citationCount')::integer, 0), 0);

    insert into public.answer_feedback (
        id, message_id, session_id, rating, flagged_for_review, source,
        category, note, user_prompt, assistant_reply, citation_entry_ids,
        citation_count, prompt_version, model_identifier, zone, was_degraded,
        safety_presentation, app_version, created_at, updated_at,
        origin, run_id, device_id
    )
    values (
        coalesce(nullif(payload->>'id', '')::uuid, gen_random_uuid()),
        (payload->>'messageID')::uuid,
        nullif(payload->>'sessionID', '')::uuid,
        v_rating,
        coalesce((payload->>'flaggedForReview')::boolean, false),
        v_source,
        v_category,
        v_note,
        v_prompt,
        v_reply,
        '{}'::uuid[],
        v_cites,
        payload->>'promptVersion',
        payload->>'modelIdentifier',
        payload->>'zone',
        (payload->>'wasDegraded')::boolean,
        v_safety,
        coalesce(payload->>'appVersion', ''),
        coalesce((payload->>'createdAt')::timestamptz, now()),
        coalesce((payload->>'updatedAt')::timestamptz, now()),
        'device_human'::eval.feedback_origin,
        v_run,
        v_device
    )
    on conflict (message_id) where message_id is not null do update set
        session_id          = excluded.session_id,
        rating              = excluded.rating,
        flagged_for_review  = public.answer_feedback.flagged_for_review or excluded.flagged_for_review,
        source              = excluded.source,
        category            = excluded.category,
        note                = excluded.note,
        user_prompt         = case when excluded.user_prompt <> '' then excluded.user_prompt
                                   else public.answer_feedback.user_prompt end,
        assistant_reply     = case when excluded.assistant_reply <> '' then excluded.assistant_reply
                                   else public.answer_feedback.assistant_reply end,
        citation_count      = excluded.citation_count,
        prompt_version      = excluded.prompt_version,
        model_identifier    = excluded.model_identifier,
        zone                = excluded.zone,
        was_degraded        = excluded.was_degraded,
        safety_presentation = excluded.safety_presentation,
        app_version         = excluded.app_version,
        updated_at          = excluded.updated_at,
        imported_at         = now()
    where public.answer_feedback.origin = 'device_human'
      and public.answer_feedback.device_id is not distinct from excluded.device_id
      and excluded.updated_at >= public.answer_feedback.updated_at;

    get diagnostics affected = row_count;
    return affected;
end $$;

revoke all on function public.submit_device_feedback(jsonb) from public;
grant execute on function public.submit_device_feedback(jsonb) to anon, authenticated;

drop view if exists public.answer_feedback_queue;
create view public.answer_feedback_queue
    with (security_invoker = on)
as
select
    message_id,
    source,
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
    citation_count,
    updated_at
from public.answer_feedback
where origin = 'device_human'
  and (rating = 'negative' or flagged_for_review)
order by flagged_for_review desc, updated_at desc;

comment on view public.answer_feedback_queue is
    'Negative or reported device rows. Filter source = report for explicit Reports.';

revoke all on table public.answer_feedback_queue from anon, authenticated;
