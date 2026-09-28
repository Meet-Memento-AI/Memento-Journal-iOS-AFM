-- Import helper for device exports (spec 041).
--
-- The app has no networking layer and does not sync, so rows arrive only via
-- AnswerFeedbackStore.exportJSONData() — a JSON array encoded by JSONEncoder
-- with default CodingKeys. That means camelCase keys ("messageID",
-- "citationEntryIDs") against snake_case columns, and .iso8601 dates. This
-- function owns that mapping so no caller has to repeat it.
--
-- Usage (from the repo root, stack running). Note the script goes in on
-- stdin: psql does NOT interpolate :'vars' in a -c command string.
--   echo "select import_answer_feedback(:'payload'::jsonb);" \
--     | docker exec -i supabase_db_memento-feedback \
--         psql -U postgres -d postgres -tA \
--         -v payload="$(jq -c . export.json)"
--
-- Upserts on message_id, mirroring the store's own one-row-per-message rule,
-- so re-importing a later export of the same device is safe and idempotent.

create or replace function import_answer_feedback(payload jsonb)
returns integer
language plpgsql
as $$
declare
    affected integer;
begin
    insert into answer_feedback (
        id, message_id, session_id, rating, flagged_for_review, source,
        category, note, user_prompt, assistant_reply, citation_entry_ids,
        prompt_version, model_identifier, zone, was_degraded,
        safety_presentation, app_version, created_at, updated_at
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
        (r ->> 'updatedAt')::timestamptz
    from jsonb_array_elements(payload) as r
    on conflict (message_id) do update set
        session_id          = excluded.session_id,
        rating              = excluded.rating,
        flagged_for_review  = excluded.flagged_for_review,
        source              = excluded.source,
        category            = excluded.category,
        note                = excluded.note,
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
end;
$$;

comment on function import_answer_feedback(jsonb) is
    'Loads an AnswerFeedbackStore.exportJSONData() array. Upserts on message_id.';
