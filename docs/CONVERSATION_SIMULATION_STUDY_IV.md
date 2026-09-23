# Conversation Simulation Study IV — spec 051

**Run:** `eval-archive/convo-sim/full-2026-09-24-spec051.jsonl`, 7,014 messages,
200 conversations, 2026-09-23 18:01 → 23:27 UTC (5h25m).
**Build:** `spec-051-reference-discipline` @ `b3dbb7d`.
**Arms:** `empty` (0) and `persona` (262) — identical to Study III.
**Pre-registration:** `eval-archive/STUDY_IV_PREREGISTRATION.md`, committed at `b3dbb7d`
**before** generation. **`k` narrowing was off.**

---

## Scorecard: 3 met, 5 falsified

| # | Prediction | Threshold | Result | |
|---|---|---|---|---|
| Q1 | Scaffolding leaks gone | `leak.*` = 0 | 34 → **3** | ✗ |
| Q2 | Unbacked dates no worse | seeded ≤ 1.4% | 1.44% → **1.80%** | ✗ |
| Q3 | Fabrication stays closed | fab 0, invented ≤ 2.0% | fab **0** ✓, invented 1.99% → **2.56%** | ✗ |
| Q4 | Empty gating recovers | ≤ 6.0% | 6.42% → **5.15%** | ✓ |
| Q5 | Citations rise | ≥ 38.6% | 38.59% → **40.27%** | ✓ |
| Q6 | Pointing unchanged | ±5pp of 15.6% | **21.5%** (+5.9pp) | ✗ |
| Q7 | Latency no regression | p50 ≤ 5.0s | 4.57s → **4.31s** | ✓ |
| Q8 | Phantom markers no rise | ≤ 251 | 251 → **404** | ✗ |

A low hit rate is what pre-registration buys. Four of the five failures are
informative; one is an outright reversal of a decision I made two commits earlier.

## Q8 — I was wrong, and the measurement says so plainly

R1 was amended during implementation. I argued that `noneNote`'s prohibition — *"no
quote or date markers this turn. Never write a journal quote, a journal date, or
italics"* — was a negative instruction, that a negative instruction is not a mechanism,
and that stating the absence would do just as well because the renderer drops unbacked
markers anyway. `noneNote` became `[Evidence: none.]`.

Markers emitted against an empty pack, as a share of `none`-state turns:

| | Study III | Study IV |
|---|---|---|
| `none`-state turns | 1,000 | 1,009 |
| …that emitted a marker | 184 (**18.4%**) | 259 (**25.7%**) |
| `dropped_markers` total | 251 | 404 |

**Removing the prohibition made it 40% worse.** The negative instruction was not a
null mechanism; it was a weak one, suppressing roughly a third of what appears without
it. "A negative instruction is not a mechanism" was too strong a reading of spec 050's
lesson, and I applied it to a case it did not cover: 050 replaced an *overloaded* token
(italics) with an unambiguous one, which is not the same as deleting a rule.

Two ways forward, and the evidence now favours the one I declined:

1. **Revert the simplification.** Cheapest, restores 18.4%, leaves the defect.
2. **Do R1 as originally written** — omit the marker grammar from the prompt when the
   pack is empty. I declined this on prefill-cost grounds, and the cost is real (eight
   teaching sites, speculative prefill, `PromptStanceSyncTests`). But 25.7% of turns
   reaching for a grammar they cannot use is a larger number than it was when I judged
   that trade, and the renderer-absorbs-it argument does not address the tokens spent.

## Q6 — the interesting win

**Pointing rose from 15.6% to 21.5%** of matched turns, and date markers from 31.4% to
31.0% (flat) while matched turns themselves rose 641 → 693.

This was pre-registered as "unchanged ±5pp" specifically to test whether slot quality
was what held pointing back. It moved +5.9pp, just outside the band. Better retrieval
put the right entry in the pack more often, and the model pointed at it more often.
**Slot relevance was part of the constraint** — not all of it, since four matched turns
in five still do not point, but a real part.

That strengthens the case for `k` narrowing (051 R4), which is built, calibrated and
still switched off. Its acceptance bar is exactly this number.

## Q1 — 91% of the leak, and a lesson about validating on past data

Leaks fell 34 → 3. The strip was validated against the archived Study III leaks and
caught **32 of 32** — but the three that remain are a different family:
`leak.sectionLabel` (*"Meet them —"*, *"Sit —"*, the recipe section names from the
prompt's own "how a reply is built" list) and one `leak.emptyBracket` (`[]`).

Neither appears in the Study III sample I validated against. Validating a filter on
past data proves it handles the past. The pattern set needs the recipe section names,
and that is a two-line follow-up.

## Q2 / Q3 — small, real, and probably the price of Q6

Unbacked dates 1.44% → 1.80% (replay-to-replay, same method both runs). Invented
material 1.99% → 2.56%, with `hall.fabricatedQuote` still at **0** — so the rise is in
`uncitedQuote` and `boldNotTheirWords`, not in invented entries.

The plain reading: the model quotes and dates more this run because retrieval gives it
more to quote and date — citations 38.6% → 40.3%, pointing +5.9pp — and a slightly
larger share of that larger volume is unbacked. Both thresholds were written as "do not
regress", which is the right shape for a defect-fix study, but neither anticipated that
fixing retrieval would increase quotation activity.

## What held

- `hall.fabricatedQuote` at **0** for a second consecutive run.
- Empty-arm gating **6.42% → 5.15%**, below the 6.0% bar it missed last time. The leak
  strip returned the difference, as Q4 predicted.
- Latency improved: seeded p50 **4.57s → 4.31s**, despite an added render pass.

## Method caveat, registered in advance and now measured

`hall.unbackedDate` did not exist during Study III, so its baseline is a replay over
archived bodies. Replay and live agree exactly on the seeded arm this run (31 = 31),
which validates the method. They diverge on the empty arm (replay 2, live 13): the live
scorer folds text before matching and is more sensitive. **All date comparisons here are
replay-to-replay**, so the divergence does not affect them — but the earlier figures I
published from replay are under-counts on the empty arm.

## Next

1. **Decide Q8.** Either revert `noneNote` or do R1 properly. Doing nothing leaves a
   defect I made worse.
2. **Add recipe section names to the scaffolding strip.** Two lines, closes Q1.
3. **Measure `k` narrowing against pointing.** Q6 says slot relevance matters; R4 is
   built and calibrated and unarmed.
