# Chunking, retrieval, and what the gate said

**Question.** Does the residual grounding problem persist because a ~3B model
cannot do more, and would finer journal chunking make RAG effective within that
constraint?

**Method.** `RetrievalGate` over the 45-question gold set, `Fixtures/corpus`,
**no model in the loop** — so this measures finding, separately from use.
Baseline archived at `eval-archive/retrieval-baseline-2026-09-23.json`.

## The numbers

| metric | value |
|---|---|
| recall@5 | **0.760** |
| precision@5 | 0.228 |
| MRR | 0.596 |
| hits | 33 / 42 answerable |
| abstention accuracy | 0.667 (1 of 3 traps leaked) |
| prompt cap (k) | 5 |

## Verdict: partially vindicated, and misdirected

**There is headroom.** recall@5 at 0.760 means roughly a quarter of answerable
questions never put the right entry in front of the model. The chunking
hypothesis is not refuted by a ceiling, and the earlier claim that "retrieval
already matches 89.5% of journalQuery turns" measured the wrong thing: a pack
being *populated* is not the right entries being *in* it.

**But the misses are not granularity-shaped.** Recall by category:

| category | n | recall |
|---|---|---|
| person | 6 | 0.900 |
| synthesis | 3 | 0.833 |
| event | 18 | 0.778 |
| pattern | 4 | 0.750 |
| **temporal** | 11 | **0.636** |

Six of the ten total misses are first-mention or date-window questions:

> "When did I start pottery classes?" · "When did I get back into running?"
> "When did Sam and I break up?" · "What was I working on last December?"

Embedding similarity cannot rank *the first* pottery entry above *any* pottery
entry — there is no semantic signal for firstness. Smaller passages produce more
pottery chunks, not an earlier-ranked one. **Chunk size is the wrong lever for
the failures that actually exist.**

**Precision is not broken, and a claim that it was would have been wrong.** The
gold set is 35 single-answer questions out of 45, so precision@5 is structurally
capped near 0.2. Observed 0.228 against a mean ceiling of 0.289 is **79% of the
achievable maximum**. Finer chunking has little to win here either.

## What the gate redirects us toward

**1. `k = 5` is the pointing story, not chunk size.** With mostly single-answer
questions, about 1.1 of 5 slots are the answer on a typical turn. In Study III
the model expanded a quote marker on 15.6% of matched turns. A model handed four
parts noise to one part signal and declining to point is plausibly *calibrated*,
not defiant. **The cheap experiment is lowering k on high-confidence turns**, not
re-chunking the corpus.

**2. Month stratification is justified — for today's retrieval, not for a
year-in-review feature.** The proposal's `MonthRollup.stratumKey` is a date
filter, and the worst-performing category is temporal. The machinery was proposed
for the wrong reason and lands on a real defect. A date-window prefilter and a
first-mention index are the targeted forms.

**3. One trap leaked.** "What have I said about my dog?" returned two entries
against an empty gold set. Retrieval handing over material that does not exist is
the same family as the model emitting markers against an empty pack, and it feeds
it.

## Agreed plan

**Track A — close the Study III residuals.** Not blocked on any of the above.

1. **Empty-pack honesty, structurally.** `ask-core@19` teaches the marker grammar
   unconditionally and `noneNote` then says "not this turn". That is a negative
   instruction, and the model ignored it on **184 turns / 237 markers**. The
   lesson of spec 050 applied to itself: when the pack is `none`, omit the marker
   grammar from the prompt entirely rather than prohibiting its use. A token never
   shown cannot be emitted. Hardening the wording is the intervention Study III
   already falsified.
2. **Scaffolding leak pass.** 34 occurrences, including `[Evidence]: none` on
   screen, against zero in the two prior studies. The only outright regression.
3. **Date scorer.** Date assertions doubled on the seeded arm (118 → 290, 250
   unflagged) and nothing checks them. Required before any month-forward UI.
4. **Pointing experiment.** Lower `k` on high-confidence turns; measure pointing
   rate against Study III's 15.6%.

**Track B — retrieval, now aimed at the measured misses.**

5. Date-window prefilter and first-mention handling for the temporal category.
   Re-run `RetrievalGate`; the bar is recall@5 above 0.760.
6. Passage granularity only if 5 leaves temporal recall short. Chunk size is not
   supported as a first move by anything in this report.

**Track C — period pathways as a product capability.** `periodSummary` /
`periodCompare` with the pack discipline of spec 050, framed as "year in review",
not as hallucination control. `themeLabel` derived from evidence the user can
open, or omitted. New counters ship with firing fixtures (spec 048 R1).

## Agreements that hold

- Pack-backed or unsaid. Study III is the proof: 56.0% → 0.
- Cap what reaches the model. The pointing-versus-slots curve argues this harder
  than "retrieve more" does.
- `coverage` / `gaps[]` with a fixed empty-window template belongs on today's Ask
  path, extracted from the period design and not held hostage to it.
- Deterministic router, Swift-computed counts, axes dropped without dual-sided
  evidence — sound, and feature work rather than current fire.
