# Study VI — results

200 conversations, 6,854 messages, **3,319 generated turns**, 4h 38m on
`ChatDiag27` (iOS 27.0). Archive: `eval-archive/convo-sim/full-2026-09-27-tier.jsonl`.
Pre-registered at `2a2ad63`; mid-run addendum at `b85d28c`.

## Scorecard

| # | Prediction | Threshold | Study IV | Study VI | |
|---|---|---|---|---|---|
| P1 | Advanced tier actually ran | ≥ 99% | `on-device` | 100% labelled | **void** |
| P2 | Latency rises but stays usable | persona ≤ 6.5s, empty ≤ 3.0s | 4.31 / 1.83 | **3.94 / 1.67** | pass (wrong direction) |
| P3 | Persona gating falls | < 9.0% | 11.0% | **11.3%** | **fail** |
| P4 | Persona invented material falls | ≤ 2.0% | 2.6% | **2.2%** | **fail** (improved) |
| P5 | Empty arm does not regress | ≤ 6.0%, invented 0 | 4.6%, 0 | **6.3%, 0** | **fail** |
| P6 | The model points better | drop-rate < 0.45 | see below | see below | **mis-specified** |
| P7 | Citation rate holds | ≥ 35% | 40.3% | **37.3%** | pass |
| P8 | Routing unchanged (control) | ±10pp, two types silent | 74.7% | **76.5%** | pass |
| P9 | Recipe still the dominant code | largest | 156 | **170** | pass |

Four of nine passed, three failed, one is void and one was badly written. The
useful findings are mostly in the four that did not come out clean.

## P1 is void, and it is the most important result

100% of generated turns carry `apple.system.on-device.afm3-core-advanced`. That
number means nothing, for two reasons established mid-run (`b85d28c`):

1. **Spec 051 never selected the model.** `OnDeviceModelTier.swift`'s header says
   the tier is "provenance and budget input only" — the OS still chooses.
2. **The label is a constant on a simulator.** The tier is inferred from
   `ProcessInfo.physicalMemory` against a 10 GB floor; inside a simulator that is
   the **host Mac's** memory, 137 GB here. Every simulator run on this machine
   infers Core Advanced, for any device, whatever model ran.

P2 corroborates it: latency went *down* (empty 1.83s → 1.67s, persona 4.31s →
3.94s). A 20B sparse model is not faster than a 3B dense one on the same silicon.
The same model almost certainly ran in both studies.

**Why the tests missed it.** `OnDeviceModelTierTests` has sixteen cases and covers
the resolver thoroughly — but every one *injects* `physicalMemoryBytes`. The one
production call site, `resolveOnDeviceTierIfNeeded()`, reads `ProcessInfo`
directly and has no test and no simulator guard. The pure core is exhaustively
tested; the single impure input is not tested at all.

**Blast radius.** Every row this harness has written since 051 landed carries that
suffix. In the spec 043 warehouse, any query that groups or filters by tier is
today grouping on a constant for all simulator-sourced rows.

## P6 was the wrong question, and the right one inverts the thesis

P6 measured dropped markers per *matched* turn. That is Goodhartable: the model
can improve the ratio by emitting fewer markers, which is what happened
(288 expanded in VI vs 430 in IV). Split by pack state, the real picture:

| | pack | turns | markers expanded | dropped | drop-rate |
|---|---|---|---|---|---|
| Study IV | matched | 693 | 430 | 6 | **1.4%** |
| Study VI | matched | 615 | 288 | 9 | **3.0%** |
| Study IV | none | 2,678 | 0 | 374 | 100% |
| Study VI | none | 2,688 | 0 | **203** | 100% |

Two things fall out, and both matter more than P6 did.

**Given evidence, the model points almost perfectly** — 97–99% of markers resolve.
Studies II and III argued reference failure here is *structural*, that a small
model cannot reliably point at evidence and Swift must do the quoting. At the
marker level that is **not what the data says**. When there is a pack, the model
addresses it correctly nearly every time.

**The real failure is markers with no pack at all.** On none-state turns the model
still emits markers — 374 in IV across 259 turns, 203 in VI across 160 turns.
Every one is dropped. The model is not failing to point; it is performing the
*gesture* of citation when it has nothing to cite.

That improved substantially: **turns emitting phantom markers fell 38% (259 → 160)
and phantom markers fell 46% (374 → 203)**. This is the run's best result, and
nothing in the pre-registration predicted it, because the pre-registration was
looking at the wrong denominator.

## The regression: a fix that never reached this branch

`leak.placeholder` fired **25 times** on the persona arm — the literal `[Evidence]`
header from the prompt reaching the user's screen. In one reply the model went
further and *fabricated* an evidence block:

```
[Evidence]
 -: the app's silence — the words linger like roots in wet soil
```

The series: Study III **24**, Study IV **0**, Study VI **25**.

This is not a new regression. Commit `d7e5020` ("Act on Study IV: revert what I
broke, and fix the leak properly this time") fixed it, with patterns verified
against real bodies and a `strippedScaffoldCount` counter. **That commit is not in
this branch's ancestry.** It exists only on `spec-051-reference-discipline` and
`study5-corpus-size-sweep`.

The port of the harness for this study hit the same wall from the other side:
`ReplyRenderStats.strippedScaffoldCount` does not compile on this branch and had
to be dropped from the row encoder. The missing counter and the returning leak are
the same absence.

**The fix does not need to be written. It needs to be merged.**

## P3 and P5: the arms moved in opposite directions to the prediction

Persona gating was flat (11.0% → 11.3%) and the empty arm got *worse*
(4.6% → 6.3%), driven by `rule.multipleQuestions` (47 → 66) and
`rule.bannedOpener` (11 → 15) — both pure recipe compliance on a journal-free
install. Since the prompt did not change and the model probably did not either,
the most likely reading is run-to-run variance rather than a regression; Study IV
was the best empty-arm number in the series and this is closer to Study III's
6.4%. Nothing here supports a claim of improvement or of damage.

P4 improved (2.6% → 2.2%) but missed its threshold, and P7 fell within tolerance
(40.3% → 37.3%) alongside the lower citation and marker volume.

## P8, the negative control, held

`followup` 74.7% → 76.5%, inside ±10pp. `acknowledgement` never fired in either
run; `reflectiveQuestion` fired once (vs zero). `correction` fired twice in 3,319
turns. The `TurnClassifier` degeneracy named in Study III is unchanged, which is
what a control passing looks like — nothing outside the registered variable moved.

## Post-hoc: a voice failure no scorer catches

Not pre-registered; measured with `scripts/eval/posthoc_voice.py` over recorded
bodies, so the instrument stayed fixed. Four prompt sites instruct the model in
the second person — *"say you can't find an entry that supports that"*
(`TurnShapeCadence.swift:53`, `RetrievalPolicy.swift:88`,
`PromptRegistry.swift:574,585`). The "you" addresses the model. When the model
transcribes the instruction's surface form rather than acting on it, the same
"you" now addresses the person, and the reply tells them *they* cannot find their
own entry. One Study IV reply contains both voices at once:

> You can't find an entry that supports that. I cannot locate anything from about
> what you wrote.

| | Study III | Study IV | Study VI |
|---|---|---|---|
| persona | 8 (0.5%) | 5 (0.3%) | 9 (0.5%) |
| empty | 0 | 0 | 0 |

Small and stable, and invisible to every existing code: it cites nothing improper
and breaks no formatting rule. `EvidenceLadder.none` already holds the sentence in
the correct voice; quoting that literal in the instruction makes transcription
harmless.

## What this study can and cannot support

It is **not** a model-tier comparison — that variable was never manipulated. It is
a clean re-measurement of the current pipeline against Study IV over the same
arms, corpus, cast, seeds and prompt, and on that basis:

- The harness is stable. Routing, policy, evidence state and zone all reproduce.
- Phantom citation markers dropped sharply, the clearest genuine improvement.
- Given evidence, the model points correctly — the structural-failure thesis
  needs narrowing to the no-evidence case.
- One shipped fix is stranded on a side branch and its absence is measurable.
- Tier provenance is unverifiable on a simulator and should stop being written.
