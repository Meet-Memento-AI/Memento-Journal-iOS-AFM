# CQ2 calibration set (MEM-334)

Fixed **100-turn** sample from the synthetic Study cast (`eval-archive/convo-sim/full-2026-09-24-spec051.jsonl`). Used to calibrate the hosted judge before judged gates count.

## Columns

| Column | Purpose |
|--------|---------|
| `turn_id`, `run_id`, `turn_index`, `persona_id`, `arm`, `channel` | Turn identity (synthetic only) |
| `user_text`, `assistant_text` | Exchange to score (fixture dialogue, not user data) |
| `human_a_q1` … `human_b_q7` | Two human raters (1–5 each criterion) |
| `judge_q1` … `judge_q7` | Hosted judge output (`judge_convo.py calibrate`) |

Criteria: **Q1, Q2, Q3, Q4, Q6, Q7** — see [conversation-quality-rubric.md](../docs/eval/conversation-quality-rubric.md).

## Workflow

1. Two raters fill `human_a_*` and `human_b_*` (spreadsheet or CSV editor).
2. Run judge (requires `JUDGE_API_KEY`, or `--dry-run` for plumbing tests):

   ```bash
   python3 scripts/eval/judge_convo.py calibrate calibration/conversation-quality-100.csv --write-judge
   ```

3. Check weighted κ ≥ **0.6**:

   ```bash
   python3 scripts/eval/judge_convo.py calibrate calibration/conversation-quality-100.csv --require-kappa
   ```

Regenerate the 100-turn sample (only when the Study cast export changes):

```bash
python3 scripts/eval/judge_convo.py build-calibration eval-archive/convo-sim/full-2026-09-24-spec051.jsonl \
  -o calibration/conversation-quality-100.csv --count 100
```
