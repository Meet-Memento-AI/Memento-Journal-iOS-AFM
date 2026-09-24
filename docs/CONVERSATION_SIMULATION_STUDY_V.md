# Conversation Simulation Study V — how big does a journal have to be?

**Run:** `full-2026-09-23-sizesweep` · `de642b5` (clean) · `ChatDiag27`, iOS 27.0
(24A434), Xcode 27.0 GA · 2026-09-24 04:47–10:52 UTC
**Design:** 100 arms (`size-001`…`size-100`), 2 conversations each, **200
sessions**, 6,790 messages, 3,395 assistant turns of which **3,332 scored as
generated** (42 `guardrailRefusal`, 18 `insight-fact@1`, 3 `unavailable` excluded)
**Pre-registration:** `eval-archive/STUDY_V_PREREGISTRATION.md`, committed
before generation
**Raw data:** `eval-archive/convo-sim/full-2026-09-23-sizesweep.jsonl`
**Full output:** `eval-archive/STUDY_V_RESULTS.md`

Studies II–IV compared two worlds: a journal with nothing in it and a journal
with 262 entries. Every real user starts between them. This sweeps the gap.

---

## Verdict

**Citation rate above five entries is flat to a degree that is hard to
overstate: Spearman ρ(n, citation rate) = +0.028 across 96 journal sizes.**
The relative threshold in `EntryRetriever.semanticThreshold` behaves exactly as
its own comment claims — an entry must stand out from *its own* corpus, so a
roughly fixed fraction clears the bar no matter how many entries there are.

That is good news and bad news in the same number, and the turn-type breakdown
separates them. When the app is actually *asked about the journal*, behaviour is
not flat at all: it climbs steeply and then saturates.

| journal size | `journalQuery` turns that cite | `hall.uncitedQuote`, all turns |
|---|---|---|
| 0 (Study IV `empty`) | 0/232 — 0.0% | 0/1,669 — 0.0% |
| 1–4 | 6/13 — 46.2% | 10/126 — **7.9%** |
| 5–7 | 10/14 — 71.4% | 1/93 — 1.1% |
| 8–10 | 9/14 — 64.3% | 2/95 — 2.1% |
| 11–15 | 20/25 — 80.0% | 7/172 — 4.1% |
| 16–25 | 47/58 — 81.0% | 7/315 — 2.2% |
| 26–50 | 97/133 — 72.9% | 11/830 — 1.3% |
| 51–75 | 103/138 — 74.6% | 18/845 — 2.1% |
| 76–100 | 111/152 — 73.0% | 12/856 — 1.4% |
| 262 (Study IV `persona`) | 294/325 — 90.5% | 44/1,721 — 2.6% |

**The product becomes useful at about ten entries**, and the harm it does
before then is not silence — it is *unbacked quotation*.

The unbacked-quote column is **not** a smooth decline, and should not be
described as one: above five entries it wanders between 1.1% and 4.1% with no
trend. What it has is a **spike in the smallest band**. That spike is not
sampling noise: 10/126 = 7.9% (Wilson 95% CI 4.4–14.0%) against 60/3,206 = 1.9%
for every larger journal (CI 1.5–2.4%) — non-overlapping intervals, a 4.2×
ratio, two-proportion z = 4.66, and a one-sided Poisson probability of 4.3×10⁻⁴
of seeing 10 events where the pooled rate predicts 2.6. The flat overall
citation rate hides it completely.

---

## Scorecard: 4 held, 3 falsified, 0 untestable

| # | Prediction | Verdict | Evidence |
|---|---|---|---|
| P1 | small-corpus cliff ≥ 10pp | **FALSIFIED** | n≤4 29/126 = 23.0% vs n≥5 999/3,206 = 31.2% — gap +8.1pp |
| P2 | size invariance \|ρ\| < 0.4 | **HELD** | ρ = **+0.028** over 96 sizes |
| P3 | phantom markers ≥ 2× at n<5 | **FALSIFIED** | 0.198/turn vs 0.160/turn — 1.24× |
| P4 | gating ≤ 6% every bin | **FALSIFIED** | worst bin 1–4: 22/126 = 17.5% |
| P5 | fabricated quotes ≤ 3% every bin | **HELD** | 0/3,332 at **every** size |
| P6 | latency < 2× from n≤10 to n≥90 | **HELD** | p50 3.65s → 3.98s — 1.09× |
| P7 | n=1 citation rate < 20% | **HELD** | 6/33 = 18.2% |

---

## P1 — falsified on the wrong denominator, and that is my error, not a result

P1 predicted a ≥10pp citation gap below five entries and measured +8.1pp, so it
fails. But the same comparison restricted to the turns where a citation is the
right answer is **+28.1pp** (46.2% → 74.3%). The cliff is real and larger than
predicted; I pre-registered it against a denominator that dilutes it with
`share`, `social` and `offdomain` turns, which cite 0% at every size by design.

This is the second time in this study that a threshold was anchored to the
wrong baseline. `STUDY_V_ENDPOINTS.md` recorded the first **before** the run:
P4's ≤6% came from the empty arm's 5.5%, when no seeded arm in four studies has
gated below 11%. P4 duly failed at 17.5% and says nothing whatever about corpus
size.

Two of the three falsifications are therefore facts about my predictions. The
discipline that makes them visible is worth more than the predictions were: a
pre-registration you are allowed to quietly reinterpret afterwards is not one.

## P2 — held, and it is the finding

ρ = +0.028 over 96 sizes; on `journalQuery` and `quantitative` turns only,
ρ = +0.003 over the same sizes (post-hoc, labelled as such in the output).

`semanticThreshold` returns `max(floorAbs, μ + 1.0σ)` once a corpus has five
entries, and a flat `floorAbs + 0.05` = 0.35 below that. Because the μ + σ term
is computed over the corpus being searched, it scales with it. A fixed share of
entries sits above one standard deviation whatever the count, so the retriever
fires at a near-constant rate from five entries to a hundred.

**What this buys:** no cold-start cliff in the engineering sense. The app does
not need a "your journal is too small" mode, and nothing had to be tuned per
size to get here.

**What it costs:** the rate is constant, so it cannot be read as confidence. A
five-entry journal retrieves as readily as a hundred-entry one, and this
harness has no relevance labels, so it cannot say whether what came back was
apt. `hall.uncitedQuote` is the closest thing to an answer, and it says the
small-journal case is materially worse.

## P3 — falsified, and it strengthens the standing thesis

The evidence pack genuinely cannot fill below five entries — mean slots when
packed is **1.62** at n≤4, 3.87 at 5–9, and 4.96 at 70–100. So the premise held.
The consequence did not: phantom markers run at 0.198/turn below five entries
and 0.160/turn above twenty, a 1.24× difference against a predicted 2×.

Phantom markers are therefore **roughly size-independent** at ~0.16/turn. The
model emits markers that resolve to nothing at about the same rate whether it
has one slot or five. That is not slot scarcity; it is the marker contract
being imperfectly followed, which is what Studies III and IV concluded the
reference limit actually is. Study V had a clean chance to attribute marker
failure to corpus size and found it cannot.

## P5 — the strongest single number in five studies

**Zero fabricated quotes in 3,332 generated turns, at every one of 100 journal
sizes.** Study II's persona arm produced 911 in 1,626 turns (56.0%). Spec 050's
marker contract is not merely effective, it is *invariant to corpus size* —
including the regime where the pack is nearly empty and the model has least to
work with.

## P6 / P7 — held, with one caveat that matters

Latency is 1.09× from n≤10 to n≥90 (p50 3.65s → 3.98s). Retrieval cost is
negligible against generation; nothing here argues for a size cap.

P7 held at 18.2% for n=1 — just inside the 20% line. But the honest reading is
that **n=1 drew only one `journalQuery` turn in two sessions**, which cited 0/1.
P7's threshold was a proxy chosen in advance and it passed on a denominator
dominated by turn types that never cite. It should not be read as evidence that
a one-entry journal behaves well; the 1–4 band's 46.2% and 7.9% unbacked quotes
are the better guide, and they point the other way.

---

## What the sweep says about the product

**Ten entries is the threshold worth designing around.** `journalQuery`
citation goes 46.2% (≤4) → 71.4% (5–7) → 80.0% (11–15) and then plateaus in the
seventies for the rest of the sweep. Onboarding that gets a user to ten entries
is buying the feature that makes the app what it claims to be.

**The small-journal failure mode is confident wrongness, not silence.** The
gating excess below five entries is not spread across codes —
`rule.multipleQuestions` is flat (10.3% vs 9.5%) while `hall.uncitedQuote` is
7.9% against 1.9% everywhere above five entries. With little to retrieve, the
model quotes things the journal does not contain. Note the effect is confined
to the smallest band rather than scaling with size: 5–7 entries already sits at
1.1%.

**A size-aware floor is the indicated fix, not a prompt change.** The flat 0.35
below five entries is the one place the retriever already knows the corpus is
too small to reason about statistically, and it is exactly where unbacked
quotation concentrates. Raising that floor, or suppressing quotation entirely
below some n, is a two-line change measurable by this harness.

---

## Threats

- **Size and recency are confounded by construction.** Arms are `suffix(n)`,
  the most recent n, so a small arm also spans a short window. A one-entry arm
  is `2026-07-22` alone; a hundred-entry arm spans back to `2026-04`. Any size
  effect could be a recency effect and this design cannot separate them.
- **Two sessions per size.** Per-size points are noise and are reported as
  inspection only; every verdict is read off the pre-registered bins. The
  smallest bins are genuinely thin — 13 `journalQuery` turns at n≤4.
- **The 262-entry comparison is suggestive, not established.** Study IV walks
  the full 10×10 cast matrix; Study V draws cells by hashing the run id. The
  turn-type mix differs, so 74.2% at n≤100 against 90.5% at 262 may be question
  draw rather than size.
- **No relevance labels**, so "cited" is never "cited aptly".
- **One authored persona; both interlocutors synthetic** — as in every prior study.
- **100 is not a large journal.** The corpus caps at 262, and the sweep stops
  at 100 by design.
- 42 turns ended in `guardrailRefusal` (designed behaviour) and **3** in an
  `unavailable` runtime fault out of 3,395 assistant turns.

## Next

1. Raise the sub-five-entry floor, or gate quotation below ~10 entries, and
   re-measure `hall.uncitedQuote` in the 1–4 band. This is the one change the
   study directly indicates.
2. Extend the sweep past 100 to settle whether the 74% → 90.5% step is size or
   question draw — same cell-draw rule on both sides.
3. Separate size from recency: an arm of n entries sampled across the whole nine
   months, against `suffix(n)` at the same n.
