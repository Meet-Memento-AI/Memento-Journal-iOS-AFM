-- Spec 043 R7 — out-of-band ingest.
--
-- Harnesses keep writing .eval-runs/ exactly as they do today; nothing here
-- runs during a test. These functions read artifacts already on disk, so a
-- clean checkout with networking disabled still runs every gate (022 R1).
--
-- Callers normalize each artifact format to one row shape in jq (see
-- scripts/eval/import_run.sh) rather than teaching SQL four formats: the
-- sweep's citations are objects, the gate's citations is an integer.

create or replace function eval.open_run(manifest jsonb)
returns uuid
language plpgsql
set search_path = eval, public, pg_temp
as $fn$
declare v_id uuid;
begin
    insert into eval.run (
        label, kind, status, provenance, prompt_version, model_identifier,
        git_sha, git_branch, git_dirty, harness, corpus_id, os_version,
        device_model, operator_kind, operator_ref, started_at, notes
    )
    values (
        manifest ->> 'label',
        (manifest ->> 'kind')::eval.run_kind,
        'open',
        coalesce((manifest ->> 'provenance')::eval.provenance, 'captured'),
        manifest ->> 'prompt_version',
        manifest ->> 'model_identifier',
        manifest ->> 'git_sha',
        manifest ->> 'git_branch',
        coalesce((manifest ->> 'git_dirty')::boolean, false),
        manifest ->> 'harness',
        coalesce(manifest ->> 'corpus_id', 'fixtures@2026-07-23'),
        manifest ->> 'os_version',
        manifest ->> 'device_model',
        coalesce((manifest ->> 'operator_kind')::eval.operator_kind, 'human'),
        manifest ->> 'operator_ref',
        coalesce((manifest ->> 'started_at')::timestamptz, now()),
        manifest ->> 'notes'
    )
    returning id into v_id;
    return v_id;
end $fn$;

create or replace function eval.close_run(p_run uuid, finished timestamptz default now())
returns void
language sql
set search_path = eval, public, pg_temp
as $fn$
    update eval.run set status = 'complete', finished_at = finished where id = p_run;
$fn$;

-- Idempotent on (run_id, item_key, rep): a re-push after a partial failure is
-- free, matching the reasoning behind spec 042's client_event_id.
create or replace function eval.ingest_generations(p_run uuid, payload jsonb)
returns integer
language plpgsql
set search_path = eval, public, pg_temp
as $fn$
declare
    v_model text;
    v_n     integer;
begin
    select model_identifier into v_model from eval.run where id = p_run;
    if not found then
        raise exception 'no such run %', p_run;
    end if;

    with ins as (
        insert into eval.generation (
            run_id, item_key, rep, prompt_category, scenario, corpus, question,
            body, chars, words, seconds, outcome, error,
            prompt_version, model_identifier, zone, degraded,
            citation_fixture_ids, citation_count, passed, gating_violation_count,
            has_history, channel, turn_kind, retrieval_mode, token_cap
        )
        select
            p_run,
            r ->> 'item_key',
            coalesce((r ->> 'rep')::int, 1),
            r ->> 'prompt_category',
            r ->> 'scenario',
            r ->> 'corpus',
            coalesce(r ->> 'question', ''),
            coalesce(r ->> 'body', ''),
            coalesce((r ->> 'chars')::int, 0),
            coalesce((r ->> 'words')::int, 0),
            (r ->> 'seconds')::double precision,
            coalesce((r ->> 'outcome')::eval.generation_outcome, 'ok'),
            nullif(r ->> 'error', ''),
            nullif(r ->> 'prompt_version', ''),
            -- The artifacts never stamped a model, so it is reconstructed from
            -- the run. That is what provenance='reconstructed' records.
            coalesce(nullif(r ->> 'model_identifier', ''), v_model),
            r ->> 'zone',
            coalesce((r ->> 'degraded')::boolean, false),
            coalesce(
                (select array_agg(x) from jsonb_array_elements_text(
                    coalesce(r -> 'citation_fixture_ids', '[]'::jsonb)) x),
                '{}'::text[]),
            coalesce((r ->> 'citation_count')::int, 0),
            (r ->> 'passed')::boolean,
            coalesce((r ->> 'gating_violation_count')::int, 0),
            coalesce((r ->> 'has_history')::boolean, false),
            r ->> 'channel',
            r ->> 'turn_kind',
            r ->> 'retrieval_mode',
            (r ->> 'token_cap')::int
        from jsonb_array_elements(payload) as r
        on conflict (run_id, item_key, rep) do nothing
        returning id
    )
    select count(*) into v_n from ins;

    -- gating mirrors ChatEvalScoring.gating(): everything except gen.*,
    -- because gen.hitTokenCap is a budget observation, not a quality fault.
    insert into eval.violation (generation_id, ord, code, detail, gating)
    select g.id, v.ord::int, v.value ->> 'code', v.value ->> 'detail',
           split_part(v.value ->> 'code', '.', 1) <> 'gen'
    from jsonb_array_elements(payload) as r
    join eval.generation g
      on g.run_id = p_run
     and g.item_key = r ->> 'item_key'
     and g.rep = coalesce((r ->> 'rep')::int, 1)
    cross join lateral jsonb_array_elements(coalesce(r -> 'violations', '[]'::jsonb))
               with ordinality as v(value, ord)
    on conflict (generation_id, ord) do nothing;

    insert into eval.generation_citation (generation_id, ord, fixture_id, entry_date, excerpt)
    select g.id, c.ord::int, c.value ->> 'fixture_id',
           (c.value ->> 'entry_date')::timestamptz, c.value ->> 'excerpt'
    from jsonb_array_elements(payload) as r
    join eval.generation g
      on g.run_id = p_run
     and g.item_key = r ->> 'item_key'
     and g.rep = coalesce((r ->> 'rep')::int, 1)
    cross join lateral jsonb_array_elements(coalesce(r -> 'citations', '[]'::jsonb))
               with ordinality as c(value, ord)
    where c.value ->> 'fixture_id' ~ '^e-\d{4}-\d{2}-\d{2}-\d+$'
    on conflict (generation_id, ord) do nothing;

    return v_n;
end $fn$;

-- Moving the baseline freezes the OLD baseline into every run that was
-- compared against it, so past comparisons do not silently rewrite themselves.
create or replace function eval.set_baseline(p_run uuid, reason text)
returns void
language plpgsql
set search_path = eval, public, pg_temp
as $fn$
declare
    v_kind   eval.run_kind;
    v_corpus text;
    v_old    uuid;
begin
    select kind, corpus_id into v_kind, v_corpus from eval.run where id = p_run;
    if not found then raise exception 'no such run %', p_run; end if;

    select id into v_old from eval.run
     where is_baseline and kind = v_kind and corpus_id = v_corpus;

    if v_old is not null then
        update eval.run
           set baseline_run_id = v_old
         where baseline_run_id is null and id <> v_old
           and kind = v_kind and corpus_id = v_corpus;
        update eval.run set is_baseline = false where id = v_old;
    end if;

    update eval.run
       set is_baseline = true,
           notes = coalesce(notes || ' | ', '') || 'baseline: ' || reason
     where id = p_run;
end $fn$;

revoke all on function eval.open_run(jsonb)                 from anon, authenticated;
revoke all on function eval.ingest_generations(uuid, jsonb) from anon, authenticated;
revoke all on function eval.close_run(uuid, timestamptz)    from anon, authenticated;
revoke all on function eval.set_baseline(uuid, text)        from anon, authenticated;
