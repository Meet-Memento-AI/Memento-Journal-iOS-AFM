# RetrievalGate (spec 044 R2)

kind: `harness_retrieval` · prompt cap 5 · report-only (no 0.85 bar on this run)

## Headline

| metric | value |
|---|---|
| questions | 12 |
| answerable | 10 |
| recall@5 | **0.600** (6/10 hit) |
| precision@5 | 0.133 |
| MRR | 0.373 |
| abstention accuracy | 0.000 (0/2 traps quiet) |
| ambient | 0/12 |

## Per question

| id | match | hit | recall | top | query |
|---|---|---|---:|---|---|
| h-01 | all | yes | 1.000 | e-2026-01-07-1, e-2026-07-22-1, e-2026-07-02-1, e-2026-06-19-1, e-2026-04-16-1 | When did I sign up for the pottery class? |
| h-02 | all | yes | 1.000 | e-2026-04-13-1, e-2026-07-19-1, e-2026-04-24-1, e-2026-04-26-1, e-2025-12-12-1 | When did I first meet Sam? |
| h-03 | all | **no** | 0.000 | e-2026-01-06-1, e-2026-02-04-1, e-2026-03-11-1, e-2026-03-17-1, e-2025-12-04-1 | When did the Atlas push begin? |
| h-04 | all | **no** | 0.000 | e-2026-04-22-1, e-2026-05-31-1, e-2026-06-01-1, e-2026-06-17-1, e-2026-06-23-1 | When did I start at Meridian? |
| h-05 | all | yes | 1.000 | e-2026-07-05-1, e-2026-06-30-1, e-2026-06-05-2, e-2026-03-08-1, e-2026-07-04-1 | When did Dario and I first argue after reconnecting? |
| h-06 | all | **no** | 0.000 | e-2026-05-29-1, e-2026-02-09-1, e-2026-05-10-1, e-2026-03-08-1, e-2026-02-26-1 | When did Nonna first come up? |
| h-07 | all | **no** | 0.000 | e-2026-02-05-1, e-2026-02-26-1, e-2026-04-16-1, e-2026-04-18-1, e-2026-07-18-1 | What happened the first time I sat at the pottery wheel? |
| h-08 | all | yes | 1.000 | e-2026-04-07-1, e-2026-04-13-1, e-2026-02-04-1, e-2025-11-03-1, e-2026-04-14-1 | What did I tell Priya about my calendar? |
| h-09 | all | yes | 1.000 | e-2026-06-24-1, e-2026-07-12-1, e-2026-06-25-2, e-2026-06-27-1, e-2026-06-26-1 | Who suggested I sell pottery at the street market? |
| h-10 | all | yes | 1.000 | e-2025-11-02-1, e-2025-11-20-1, e-2025-11-29-1 | What did Maya and I do that lazy Sunday in November? |
| h-11 | none | **no** | 0.000 | e-2026-07-06-2, e-2026-05-01-1, e-2026-06-18-1, e-2026-05-12-1, e-2026-05-16-1 | What have I written about learning to sail? |
| h-12 | none | **no** | 0.000 | e-2026-06-30-1, e-2026-05-30-1, e-2026-06-02-1, e-2026-06-14-1, e-2026-06-11-1 | When did I move to Lisbon? |

## Misses

### h-03 — When did the Atlas push begin?
- expected: e-2025-12-05-1
- ranks: ∅
- prompt: e-2026-01-06-1, e-2026-02-04-1, e-2026-03-11-1, e-2026-03-17-1, e-2025-12-04-1
- ambient: false

### h-04 — When did I start at Meridian?
- expected: e-2026-05-01-1
- ranks: ∅
- prompt: e-2026-04-22-1, e-2026-05-31-1, e-2026-06-01-1, e-2026-06-17-1, e-2026-06-23-1
- ambient: false

### h-06 — When did Nonna first come up?
- expected: e-2025-12-18-1
- ranks: ∅
- prompt: e-2026-05-29-1, e-2026-02-09-1, e-2026-05-10-1, e-2026-03-08-1, e-2026-02-26-1
- ambient: false

### h-07 — What happened the first time I sat at the pottery wheel?
- expected: e-2026-01-08-1
- ranks: ∅
- prompt: e-2026-02-05-1, e-2026-02-26-1, e-2026-04-16-1, e-2026-04-18-1, e-2026-07-18-1
- ambient: false

