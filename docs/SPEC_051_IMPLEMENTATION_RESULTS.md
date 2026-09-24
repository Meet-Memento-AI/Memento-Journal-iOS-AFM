# Spec 051 — what landed, and what the measurements said

Companion to [`specs/051`](../specs/051-reference-discipline-and-temporal-retrieval.md).
Every figure here comes from a gate run or a replay over an archived study; none is
hand-counted.

## Retrieval

| | before | after |
|---|---|---|
| fitted recall@5 | 0.760 | **0.783** |
| fitted MRR | 0.596 | **0.604** |
| **held-out recall@5** | 0.600 | **0.700** |
| held-out MRR | 0.373 | **0.492** |
| abstention (fitted) | 0.667 | 0.667 |

**The held-out set changed the answer twice.** It exists because the shipped weights
were fitted on the only gold set there was, and `RETRIEVER_GRID=1` would fit them
further on the same 45 questions.

First, it showed retrieval was worse than anyone had been quoting: **0.600, not
0.760** — sixteen points — with abstention 0.000 against the fitted set's 0.667. Both
its traps leaked.

Second, it rejected the better-scoring weight. An origin ramp at 0.50 gives the best
fitted number in the series (0.795) and moves held-out **not at all**; at 0.25 fitted
gives back 0.012 and held-out rises a full ten points. The strong ramp also broke a
held-out question that had been passing — "the first argument *after* reconnecting" is
a constrained first, not the oldest argument in the journal.

## Two things that would have shipped silently

**A knob that does nothing.** The within-window σ relaxation was measured at 1.00,
0.25 and 0.00: every metric on both gold sets bit-identical. The windowed branch
already returns `touched` entries when nothing clears the bar, so σ was never what
ranks inside a window. Deleted rather than shipped; the December miss has some other
cause and is still open.

**A threshold above its own range.** The `k`-narrowing margin was first written as
0.40, reasoning about what "decisive" should mean. Margins run min 0.000, median
0.035, max **0.317** — 0.40 is above every margin either gold set produces. It would
have narrowed nothing, ever, while reading in the source like a working feature. That
is a dead check wearing a different costume, and only the calibrate-don't-guess rule
caught it. Shipped at 0.10: narrows ~3 questions in 10 on both sets, costs no recall
on either.

## A claim I published and have now withdrawn

Study III's write-up and paper both report that dates "went the wrong way" — seeded-arm
assertions 118 → 290, with 250 passing clean. That counted *assertions*, not errors.
Replayed with `hall.unbackedDate`, the scorer built for exactly this:

| | unbacked dates | rate |
|---|---|---|
| Study II persona | 63 / 1,626 | 3.9% |
| **Study III persona** | **24 / 1,661** | **1.4%** |
| Study II empty | 9 / 1,760 | 0.5% |
| Study III empty | 1 / 1,667 | 0.1% |

Spec 050 improved date grounding by more than half. The count rose because `{{date:N}}`
made the model date things more often, and a far higher share of those dates are
correct by construction because the renderer expands them from the entry's own
timestamp. Measuring salience and calling it error is the same mistake as reading zero
violations as a clean run, pointed the other way.

## Scaffolding

The `stripScaffolding` pass catches **32 of 32** leaks in the archived Study III run —
`[Evidence]: none`, `[Today: …]`, turn tags, legend lines. Placement is load-bearing
and constrained on four sides; the reasoning is in the source and in R2.

## Still open

- **Study IV** — pre-register, run both arms at 100, confirm `dropped_markers` → ~0,
  `leak.*` → 0, `hall.unbackedDate` at scale, and the pointing rate against 15.6%.
- **`k` narrowing is unarmed** behind `MEMENTO_NARROW_K`. It is calibrated for recall,
  not yet justified on pointing, which is the bar that decides whether it defaults on.
- **The December miss** — "What was I working on last December?" still returns five
  December entries and ranks the answer sixth. The window works; something else ranks.
- **`.nearbyOnly`** — declared, given prompt copy, handled in four files, produced by
  nothing (051 finding 9).
