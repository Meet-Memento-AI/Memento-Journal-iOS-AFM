# Study V — pre-registration

**Written and committed before any generation.** Studies II–IV compared two
worlds: a journal with nothing in it and a journal with 262 entries. Nothing
measured what happens *between* them, which is where every real user starts.

Study V sweeps journal size. One arm per size `n = 1…100`, two conversations
each, 200 sessions total. Everything else is held at the Study IV settings.

---

## Design

| | Study V |
|---|---|
| base | `study5-corpus-size-sweep` from `373ea9b` |
| arms | 100 — `size-001` … `size-100` |
| runs per arm | 2 |
| sessions | **200** |
| length | 20–50 messages, seeded per run id (unchanged since Study II) |
| corpus | the n **most recent** entries of the 262-entry persona journal |
| device | `ChatDiag27` (iPhone 17 Pro, 27.0/24A434) — the only simulator with model assets |
| scorers | the same nine, unchanged |

**Entry selection is `suffix(n)`, not a random sample and not the oldest n.**
A person with seven entries wrote them over recent weeks and their newest is
today's. Taking the oldest seven would model someone who journalled for a
fortnight nine months ago and stopped — a different question. The cost is that
a small arm also spans a short window, so **size and recency move together**;
`entry_date_range` is recorded per arm so the confound is measurable rather
than hidden. This is the study's main threat and it is named up front.

**Question type is drawn from the run id**, `FNV-1a(run_id) % 100`, not walked
in order. Studies II–IV run 100 conversations per arm and walk the 10×10 cast
matrix exactly once. Two conversations per arm walked in order would ask every
journal size *the same two questions*, and any trend across sizes could as
easily be a property of those two questions. Hashing decorrelates question
type from corpus size and still replays exactly.

---

## The mechanism this study is really testing

`EntryRetriever.semanticThreshold` is **relative**, not absolute:

```
n <  minCorpusForSigma (5):  threshold = floorAbs + 0.05          = 0.35 flat
n >= 5:                      threshold = max(floorAbs, μ + max(1.0σ, minSigmaMargin))
```

An entry must stand out **from its own corpus**. That has a consequence worth
stating before the data arrives: under any roughly bell-shaped similarity
distribution, a fixed fraction of entries sit above μ + 1σ *regardless of how
many there are*. If that holds, citation rate is **size-invariant** above n=5 —
a 5-entry journal would cite as readily as a 100-entry one.

That is either the design working (no cold-start cliff) or the design failing
(stated confidence does not track how much evidence exists). Which one it is
depends on whether the cited entry is actually apt, and this harness has no
relevance labels — so the study reports the rate and says plainly what it
cannot settle. `maxEntries = 5` also means a journal smaller than five can
never fill the evidence pack.

---

## Predictions

| # | Prediction | Threshold | Why |
|---|---|---|---|
| **P1** | A small-corpus cliff exists | citation rate over n∈[1,4] is **≥ 10pp below** n∈[5,100] | n<5 takes the flat 0.35 floor; 0.35 is above `semanticFloorAbs` and there is no σ term to fall below it |
| **P2** | Above the cliff, citation rate is size-invariant | **\|Spearman ρ(n, citation rate)\| < 0.4** over n∈[5,100] | the relative threshold auto-scales with the corpus |
| **P3** | Phantom markers fall as the journal grows | `droppedMarkerCount` per generated turn at n∈[1,4] is **≥ 2×** that at n∈[20,100] | `slotCount < 5` below n=5, so a `{{quote:4}}` has nothing to resolve to |
| **P4** | Gating does not regress at any size | gated share **≤ 6%** in every size bin | the empty arm was 5.5% (Study II); rule/leak failures should not be a function of corpus size |
| **P5** | Fabricated quotes stay near zero at every size | `hall.fabricatedQuote` **≤ 3%** of generated turns in every bin | 050's marker contract should not be size-dependent; Study III put this at 2.0% |
| **P6** | Latency grows sublinearly | p50 model seconds at n∈[90,100] **< 2×** that at n∈[1,10] | retrieval is O(n) embedding work but the model dominates |
| **P7** | A one-entry journal does not assert relevance it cannot have | citation rate at n=1 **< 20%** | with one entry and a hashed question draw, most questions cannot be answered from it; a high rate here is forced relevance, not grounding |

**P2 is the prediction that matters.** It is the one that makes a claim about
the design rather than about the model, and it is the one most likely to be
wrong in an interesting way. If citation rate instead climbs steadily with n,
the relative threshold is not behaving as its own comment describes and the
cold-start story in Studies II–IV was incomplete.

**P7 is the one with a product consequence.** If it fails, the honest fix is a
size-aware floor, not a prompt change.

---

## What would falsify the standing thesis

Studies III–IV concluded the reference limit was the **contract**, not the
parameter count. Study V cannot re-test that directly, but it can damage it:
if `hall.*` rates rise with corpus size (P5 failing at large n only), then the
contract holds only while the evidence pack is small, and "the contract fixed
it" becomes "the contract fixed it for short packs" — a materially weaker
claim that would need saying.

---

## Analysis plan, fixed now

- Per-size aggregates, then **size bins** `[1,4] [5,9] [10,19] [20,39] [40,69] [70,100]`.
  Two sessions per size is far too few to read a single size's number; the bins
  are where the trend is read, and no per-size point will be reported as a result.
- Spearman ρ on the per-size series for P2, with n as the unit (96 points), not
  per-turn.
- Every rate reported as numerator/denominator, never a bare percentage.
- `entry_date_range` reported alongside every bin, because of the recency confound.
- Comparison back to Studies II–IV at their own sizes: 0 entries (empty arm)
  and 262 entries (persona arm) are the endpoints this sweep sits between.

## Threats carried

- **Size and recency are confounded by construction** (above).
- **Two sessions per size.** The sweep is wide, not deep; bins carry the weight.
- **One authored persona**, as in every prior study.
- **Both interlocutors synthetic**, as before.
- **No relevance labels**, so "cited" is not "cited aptly". P7's threshold is a
  proxy chosen in advance, not a measurement of aptness.
- **262 entries is the ceiling** of the corpus, so n=100 is not "a large
  journal" in absolute terms — it is the largest this fixture supports at 100.
