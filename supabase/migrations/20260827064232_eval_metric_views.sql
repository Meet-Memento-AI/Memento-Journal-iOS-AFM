-- Spec 043 — metric views.
--
-- Every view carries its scope in the GROUP BY, so a mixed result is visibly
-- mixed rather than averaged into one wrong number. There is deliberately no
-- unscoped aggregate over answer_feedback.

-- ── 1. Quality by category. TWO views, because there are two vocabularies:
-- feedback categories (wrongRecall/tone/...) and prompt shapes (mood/work/...).
-- Merging them is exactly the silent corruption this split prevents.

create view public.v_real_quality_by_category with (security_invoker = on) as
select
    category,
    count(*)                                                    as n,
    count(*) filter (where rating = 'positive')                 as positive,
    count(*) filter (where rating = 'negative')                 as negative,
    count(*) filter (where flagged_for_review)                  as reported,
    round(100.0 * count(*) filter (where rating = 'positive')
          / nullif(count(*) filter (where rating <> 'none'), 0), 1) as pct_positive
from public.answer_feedback
where origin = 'device_human'
group by category;

create view eval.v_judgment_by_origin with (security_invoker = on) as
select
    f.origin,
    r.label as run_label,
    f.category,
    count(*)                                     as n,
    count(*) filter (where f.rating = 'negative') as negative,
    count(*) filter (where f.flagged_for_review)  as reported
from public.answer_feedback f
join eval.run r on r.id = f.run_id
group by f.origin, r.label, f.category;

create view eval.v_run_quality_by_category with (security_invoker = on) as
select
    g.run_id, r.label, g.prompt_category, v.family,
    count(distinct g.id)                                  as generations,
    count(v.*) filter (where v.gating)                    as gating_violations,
    round(count(v.*) filter (where v.gating)::numeric
          / nullif(count(distinct g.id), 0), 4)           as gating_per_generation
from eval.generation g
join eval.run r on r.id = g.run_id
left join eval.violation v on v.generation_id = g.id
group by g.run_id, r.label, g.prompt_category, v.family;

-- ── 2. Retrieval grounding.

create view eval.v_grounding with (security_invoker = on) as
select
    g.run_id, r.label,
    count(*)                                                        as generations,
    avg(g.citation_count)                                           as mean_citations,
    count(*) filter (where g.citation_count = 0)                    as uncited,
    round(count(*) filter (where g.citation_count = 0)::numeric
          / nullif(count(*), 0), 4)                                 as uncited_rate,
    count(*) filter (where exists (
        select 1 from eval.violation v
         where v.generation_id = g.id and v.family = 'hall'))        as hallucination_rows,
    count(*) filter (where exists (
        select 1 from eval.violation v
         where v.generation_id = g.id and v.family = 'gold'))        as gold_citation_faults,
    avg(g.recall)    filter (where g.recall is not null)             as mean_recall,
    avg(g.precision) filter (where g.precision is not null)          as mean_precision
from eval.generation g
join eval.run r on r.id = g.run_id
group by g.run_id, r.label;

-- ── 3/4. Run summary: throughput, and the denominator every regression needs.

create view eval.v_run_summary with (security_invoker = on) as
select
    r.id as run_id, r.label, r.kind, r.corpus_id, r.status, r.provenance,
    r.prompt_version, r.model_identifier, r.git_sha, r.is_baseline,
    r.baseline_run_id, r.operator_kind, r.started_at, r.finished_at,
    count(g.*)                                              as generations,
    count(g.*) filter (where g.outcome <> 'ok')             as failures,
    -- If this reads > 1 the run-level prompt_version is a label, not a fact,
    -- and any comparison must group by the per-generation column instead.
    count(distinct g.prompt_version)                        as distinct_prompt_versions,
    sum(g.gating_violation_count)                           as gating_violations,
    round(sum(g.gating_violation_count)::numeric
          / nullif(count(g.*), 0), 4)                       as gating_rate,
    round(count(g.*) filter (where g.gating_violation_count > 0)::numeric
          / nullif(count(g.*), 0), 4)                       as dirty_rate,
    avg(g.seconds)                                          as mean_seconds,
    percentile_cont(0.5)  within group (order by g.seconds) as p50_seconds,
    percentile_cont(0.95) within group (order by g.seconds) as p95_seconds,
    avg(g.citation_count)                                   as mean_citations
from eval.run r
left join eval.generation g on g.run_id = r.id
group by r.id;

-- Which baseline applies: the frozen one if recorded, else the current flag.
create view eval.v_run_baseline with (security_invoker = on) as
select
    r.id as run_id,
    coalesce(
        r.baseline_run_id,
        (select b.id from eval.run b
          where b.is_baseline and b.kind = r.kind and b.corpus_id = r.corpus_id)
    ) as baseline_run_id
from eval.run r;

create view eval.v_regression with (security_invoker = on) as
select
    cur.label as run, base.label as baseline,
    cur.model_identifier is not distinct from base.model_identifier as same_model,
    cur.corpus_id = base.corpus_id                                  as same_corpus,
    cur.gating_rate      - base.gating_rate      as d_gating_rate,
    cur.dirty_rate       - base.dirty_rate       as d_dirty_rate,
    cur.mean_citations   - base.mean_citations   as d_mean_citations,
    cur.p50_seconds      - base.p50_seconds      as d_p50_seconds,
    cur.generations, base.generations            as baseline_generations
from eval.v_run_summary cur
join eval.v_run_baseline b on b.run_id = cur.run_id
join eval.v_run_summary base on base.run_id = b.baseline_run_id
where cur.run_id <> base.run_id;

-- The one you actually read after a run: WHICH prompts moved.
create view eval.v_regression_by_item with (security_invoker = on) as
select
    cur.run_id, cur.item_key, cur.prompt_category, cur.question,
    base.gating_violation_count as baseline_violations,
    cur.gating_violation_count  as current_violations,
    case
        when base.gating_violation_count = 0 and cur.gating_violation_count > 0
            then 'regressed'
        when base.gating_violation_count > 0 and cur.gating_violation_count = 0
            then 'fixed'
        when cur.gating_violation_count > base.gating_violation_count then 'worse'
        when cur.gating_violation_count < base.gating_violation_count then 'better'
        else 'unchanged'
    end as verdict,
    base.citation_count as baseline_citations,
    cur.citation_count,
    cur.seconds - base.seconds as d_seconds
from eval.generation cur
join eval.v_run_baseline b on b.run_id = cur.run_id
join eval.generation base
  on base.run_id = b.baseline_run_id
 and base.item_key = cur.item_key
 and base.rep = cur.rep
-- Without this the baseline run compares against itself, doubling the row
-- count and reporting 100 spurious 'unchanged' items. v_regression has the
-- same guard.
where cur.run_id <> b.baseline_run_id;

-- Guardrail: name the comparisons that are not comparisons.
create view eval.v_incomparable_runs with (security_invoker = on) as
select run, baseline, same_model, same_corpus
from eval.v_regression
where not (same_model and same_corpus);

-- ── Access. Same posture as 20260825122636: closed by default, and the
-- default privileges revoked so future objects in this schema stay closed.

alter table eval.run                 enable row level security;
alter table eval.generation          enable row level security;
alter table eval.generation_citation enable row level security;
alter table eval.violation           enable row level security;
alter table eval.violation_code      enable row level security;
alter table eval.article             enable row level security;
alter table eval.article_row         enable row level security;

revoke all on all tables    in schema eval from anon, authenticated;
revoke all on all functions in schema eval from anon, authenticated;
revoke usage on schema eval from anon, authenticated;

alter default privileges in schema eval revoke all on tables    from anon, authenticated;
alter default privileges in schema eval revoke all on functions from anon, authenticated;
