-- Spec 042 — verification-only device write path (2026-09-11).
--
-- Live project already has public.answer_feedback + service-role
-- import_answer_feedback(jsonb, text). There is no feedback schema.
-- import_answer_feedback is not SECURITY DEFINER and is revoked from
-- anon/authenticated, so a shipping client cannot call it.
--
-- This migration adds:
--   * device_id on public.answer_feedback (erase key; null on warehouse rows)
--   * submit_device_feedback(jsonb) — write-only, security definer, anon execute
--   * erase_device_feedback(uuid)   — deletes only this device's device_human rows
--
-- Server-side redaction: journal-derived user_prompt / assistant_reply are stored
-- only when source = 'report' AND textIncluded is true. citation_entry_ids is
-- always empty (count may travel in the payload; UUIDs are not stored).

alter table public.answer_feedback
    add column if not exists device_id uuid;

comment on column public.answer_feedback.device_id is
    'Install-scoped verification id for spec 042 live ingest. Null on eval/warehouse rows. Used only for consented remote erase.';

create index if not exists answer_feedback_device_idx
    on public.answer_feedback (device_id)
    where device_id is not null;

insert into eval.run (label, kind, status, provenance, corpus_id, operator_kind, started_at)
values (
    'device-verification-live',
    'manual_device_session',
    'open',
    'captured',
    'live-user-journal',
    'human',
    now()
)
on conflict (label) do nothing;

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

    insert into public.answer_feedback (
        id, message_id, session_id, rating, flagged_for_review, source,
        category, note, user_prompt, assistant_reply, citation_entry_ids,
        prompt_version, model_identifier, zone, was_degraded,
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

create or replace function public.erase_device_feedback(device_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    affected integer := 0;
begin
    if device_id is null then
        raise exception 'device_id required' using errcode = '22023';
    end if;

    delete from public.answer_feedback
     where origin = 'device_human'
       and public.answer_feedback.device_id = erase_device_feedback.device_id;

    get diagnostics affected = row_count;
    return affected;
end $$;

comment on function public.submit_device_feedback(jsonb) is
    'Spec 042 write-only ingest for volunteered device feedback. Anon execute; no SELECT.';
comment on function public.erase_device_feedback(uuid) is
    'Spec 042 remote erase for one verification device_id. device_human rows only.';

revoke all on function public.submit_device_feedback(jsonb) from public;
revoke all on function public.erase_device_feedback(uuid) from public;
grant execute on function public.submit_device_feedback(jsonb) to anon, authenticated;
grant execute on function public.erase_device_feedback(uuid) to anon, authenticated;

-- Table remains closed: no SELECT/INSERT/UPDATE/DELETE for anon.
revoke all on table public.answer_feedback from anon, authenticated;
revoke all on table public.answer_feedback_queue from anon, authenticated;
revoke all on table public.v_real_feedback from anon, authenticated;
