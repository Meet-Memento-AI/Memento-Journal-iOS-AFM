#!/usr/bin/env bash
# Spec 043 R7 — import eval artifacts into the warehouse.
#
# Harnesses stay local and credential-free (spec 022 R1). This reads what they
# already wrote to .eval-runs/ and pushes it out-of-band.
#
#   scripts/eval/import_run.sh \
#     --kind harness_sweep --label sweep-2026-08-23 \
#     --prompt-version ask@15 --model afm-on-device \
#     --provenance reconstructed \
#     --target local \
#     .eval-runs/sweep/sweep-*.jsonl
#
# --prompt-version and --model are REQUIRED for model-running kinds: spec 022
# R1 discards a run that cannot name them, and the DB enforces it.
set -euo pipefail

KIND=""; LABEL=""; PROMPT=""; MODEL=""; PROV="captured"; TARGET="local"
CORPUS="fixtures@2026-07-23"; NOTES=""; OPERATOR="human"; BASELINE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind) KIND="$2"; shift 2;;
    --label) LABEL="$2"; shift 2;;
    --prompt-version) PROMPT="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --provenance) PROV="$2"; shift 2;;
    --corpus) CORPUS="$2"; shift 2;;
    --notes) NOTES="$2"; shift 2;;
    --operator) OPERATOR="$2"; shift 2;;
    --target) TARGET="$2"; shift 2;;
    --baseline) BASELINE=1; shift;;
    *) break;;
  esac
done
FILES=("$@")

[[ -n "$KIND"  ]] || { echo "--kind required" >&2; exit 2; }
[[ -n "$LABEL" ]] || { echo "--label required" >&2; exit 2; }
[[ ${#FILES[@]} -gt 0 ]] || { echo "no artifact files given" >&2; exit 2; }
case "$KIND" in
  harness_sweep|harness_gate|harness_agentic)
    [[ -n "$PROMPT" && -n "$MODEL" ]] || {
      echo "--prompt-version and --model are required for $KIND (spec 022 R1)" >&2; exit 2; };;
esac

psql_run() {
  if [[ "$TARGET" == "local" ]]; then
    docker exec -i supabase_db_memento-feedback psql -U postgres -d postgres -tA "$@"
  else
    # Cloud needs a real connection string with the DB password. `supabase
    # status` reports the LOCAL stack, so it must not be used here. Supply
    # SUPABASE_DB_URL, or let this fall back to the pooler URL the CLI cached
    # at link time (which still needs the password substituted in).
    local url="${SUPABASE_DB_URL:-}"
    if [[ -z "$url" && -f supabase/.temp/pooler-url ]]; then
      url=$(cat supabase/.temp/pooler-url)
    fi
    [[ -n "$url" ]] || {
      echo "set SUPABASE_DB_URL to the project connection string for --target cloud" >&2
      exit 2; }
    command -v psql >/dev/null || {
      echo "psql not found on PATH; required for --target cloud" >&2; exit 2; }
    psql "$url" -tA "$@"
  fi
}

GIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
GIT_DIRTY=$([[ -n "$(git status --porcelain 2>/dev/null)" ]] && echo true || echo false)

MANIFEST=$(jq -n \
  --arg label "$LABEL" --arg kind "$KIND" --arg pv "$PROMPT" --arg model "$MODEL" \
  --arg prov "$PROV" --arg sha "$GIT_SHA" --arg branch "$GIT_BRANCH" \
  --argjson dirty "$GIT_DIRTY" --arg corpus "$CORPUS" --arg notes "$NOTES" \
  --arg op "$OPERATOR" \
  '# NOTE: do not use select() for optional values here. In jq, {k: empty}
   # makes the ENTIRE object construction produce nothing, so one empty
   # argument silently yields an empty manifest rather than a missing key.
   def opt: if . == "" then null else . end;
   {label:$label,kind:$kind,prompt_version:($pv|opt),
    model_identifier:($model|opt),provenance:$prov,git_sha:($sha|opt),
    git_branch:($branch|opt),git_dirty:$dirty,corpus_id:$corpus,
    notes:($notes|opt),operator_kind:$op}')

RUN=$(echo "select eval.open_run(:'m'::jsonb);" | psql_run -v m="$MANIFEST")
echo "run: $LABEL -> $RUN"

# Normalize each artifact shape to the one row shape ingest_generations takes.
normalize() {
  case "$KIND" in
    harness_sweep)
      jq -c -s '[.[] | {
        item_key: (.index|tostring), rep: 1,
        prompt_category: .category, question: .question, body: .body,
        chars: .chars, words: .words, seconds: .seconds,
        outcome: (if (.error // "") != "" then "error" else "ok" end),
        error: .error, prompt_version: .promptVersion, zone: .zone,
        degraded: .degraded, has_history: .hasHistory,
        citation_count: .citationCount,
        citation_fixture_ids: [(.citations // [])[] | .id],
        citations: [(.citations // [])[] | {fixture_id: .id, entry_date: .date, excerpt: .excerpt}],
        gating_violation_count: (.gatingViolations // 0),
        violations: [(.violations // [])[] | (if type=="object" then . else {code: ., detail: null} end)]
      }]' ;;
    harness_gate)
      jq -c '[.[] | {
        # scenario alone is NOT unique (61 distinct across 100 rows), so
        # keying on it would silently drop rows via ON CONFLICT DO NOTHING.
        # scenario+question is unique and stable across runs.
        item_key: (.scenario + " :: " + .question), rep: (.rep // 1),
        scenario: .scenario, corpus: .corpus, question: .question, body: .body,
        chars: .chars, seconds: .seconds,
        outcome: (if (.error // "") != "" then "error" else "ok" end),
        error: .error, prompt_version: .promptVersion,
        passed: .passed, citation_count: (.citations // 0),
        gating_violation_count: ([(.violations // [])[] | select((.code|split(".")[0]) != "gen")] | length),
        violations: (.violations // [])
      }]' ;;
    *) jq -c '.' ;;
  esac
}

TOTAL=0
for f in "${FILES[@]}"; do
  PAYLOAD=$(normalize < "$f")
  # The statement goes in on STDIN with the JSON dollar-quoted. Passing a
  # multi-hundred-KB payload as a psql -v variable hits ARGV_MAX
  # ("argument list too long"); stdin has no such limit.
  N=$(printf "select eval.ingest_generations('%s'::uuid, \$ej\$%s\$ej\$::jsonb);" \
        "$RUN" "$PAYLOAD" | psql_run)
  echo "  $(basename "$f"): $N rows"
  TOTAL=$((TOTAL + N))
done

echo "select eval.close_run(:'r'::uuid);" | psql_run -v r="$RUN" > /dev/null
[[ $BASELINE -eq 1 ]] && {
  echo "select eval.set_baseline(:'r'::uuid, :'why');" \
    | psql_run -v r="$RUN" -v why="set by import_run.sh" > /dev/null
  echo "  marked as baseline"; }
echo "imported $TOTAL generations into $LABEL"
