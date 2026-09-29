# Study IV — pre-registration

Committed **before** any generation, as Study III was. Git shows this commit preceding
the run artifact, which is what makes the predictions falsifiable rather than fitted
afterwards.

- **Registered:** 2026-09-23
- **Design:** identical to Study III — arms `empty` (0 entries) and `persona`
  (262 entries, `Fixtures/corpus`), 100 conversations each, 20–50 messages, same
  seeds, same cast, same scorers plus `hall.unbackedDate`.
- **Only variable:** spec 051 — the scaffolding strip, the simplified pack notes, and
  the retrieval changes (origin ramp, cue coverage). `k` narrowing stays **off**;
  `MEMENTO_NARROW_K` is not set, so that path is measured separately or not at all.
- **Baseline:** `eval-archive/convo-sim/full-2026-09-23-resim.jsonl` (Study III).

## What is being tested

051 is defect work, not a new capability, so the predictions are mostly "the thing that
broke is fixed and nothing else moved". The one open question is whether better
retrieval changes what the model does with evidence — more relevant slots could raise
pointing, or could leave it exactly where it was, which would say the 15.6% is about
the model and not about slot quality.

## Predictions

| # | Prediction | Threshold | Falsified if |
|---|---|---|---|
| Q1 | Scaffolding leaks are gone | `leak.*` total **0** on both arms (was 34 seeded) | ≥ 1 |
| Q2 | Unbacked dates do not regress | seeded `hall.unbackedDate` ≤ **1.4%**; empty ≤ 0.1% | above either |
| Q3 | Fabrication stays closed | seeded `hall.fabricatedQuote` **0**, invented material ≤ 2.0% | above either |
| Q4 | Empty-arm gating recovers | ≤ **6.0%** (was 6.4%; the leak strip should return the difference) | > 6.0% |
| Q5 | Citations rise with recall | seeded turns with ≥1 citation ≥ **38.6%** | < 38.6% |
| Q6 | **Pointing is unchanged** | quote-marker expansion on matched turns within ±5pp of **15.6%** | outside |
| Q7 | Latency does not regress | seeded p50 ≤ **5.0s** (was 4.57s) | > 5.0s |
| Q8 | Phantom markers do not rise | seeded `dropped_markers` ≤ **251** | > 251 |

**Q6 is the interesting one.** Retrieval got better on both gold sets, so the packs this
run builds should contain the right entry more often. If pointing still sits at ~15.6%,
slot quality was not what held it back, and the remaining gap is about how the model
treats an evidence list — which would make the `k` narrowing already built (R4) the
next thing to measure rather than a retrieval change. If pointing rises, slot relevance
was part of it and R4's case strengthens.

**Q8 is a deliberate non-prediction of improvement.** R1 was amended during
implementation: the marker grammar is still taught unconditionally in the cached
instructions, and only the pack notes changed. Phantom markers should therefore be
roughly flat. A large fall would mean the notes mattered more than the analysis said;
a rise would mean simplifying them made things worse.

## Known limitations, registered in advance

- One authored seeded world; both interlocutors synthetic. Unchanged.
- Conversations are not paired past turn 1 — a changed assistant produces a changed
  conversation, so only distributions compare.
- `hall.unbackedDate` is new, so Study III's figure for it is a replay over archived
  bodies rather than a live measurement. Same bodies, same scorer, but the comparison
  is replay-to-live.
- `k` narrowing is not exercised. Its acceptance bar (pointing above 15.6%) cannot be
  settled by this run.
