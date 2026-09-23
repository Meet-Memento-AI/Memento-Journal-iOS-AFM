# Conversation Simulation Study III — the renderer result

**Run:** `eval-archive/convo-sim/full-2026-09-23-resim.jsonl`, 6,858 messages,
200 conversations, 2026-09-22 23:10 → 2026-09-23 04:17 UTC (5h07m).
**Build:** `study3-resim` @ `1689c22` — `session1-scorer-repair` @ `a8d450d`, which
carries spec 050 (`EvidencePack` + typed markers + `ReplyRenderer`).
**Arms:** `empty` (0 entries) and `persona` (262 entries) — identical to Study II.
**Pre-registration:** `eval-archive/STUDY_III_PREREGISTRATION.md`, committed at
`1689c22` **before** any generation.
**Paper:** https://claude.ai/artifact/LxKoeRepUjqb3kg3FrPkYB

---

## Verdict

Spec 050 worked, by a wide margin, and got slightly faster doing it.

| | Study II | Study III |
|---|---|---|
| invented material, 262-entry journal | 56.6% | **2.0%** |
| `hall.fabricatedQuote` | 911 | **0** |
| seeded p50 latency | 4.50s | **4.57s** |
| seeded citation rate | 40.5% | 38.6% |

This is the largest quality movement in the series, and it is the second time the
same move has produced one: take a decision away from the model and quality
improves. The first was channel selection (36.8% → 0% on the empty arm); this is
quotation.

**But the previous report's explanation for why it would work was wrong**, and the
pre-registration is what makes that sayable rather than arguable.

## Scorecard

| # | Prediction | Result | |
|---|---|---|---|
| P1 | persona fabricated quotes < 10% | **0.0%** | met |
| P2 | empty-arm gating ≤ 6.0% | **6.4%** | **falsified** |
| P3 | invented dates on empty ≤ 2 | **1** | met |
| P4 | model needs cleanup on ≥ 25% of seeded turns | **2.4%** | **falsified** |
| P5 | followup within ±10pp; correction stays ~0 | 76.7%, correction 2 | met |
| P6 | seeded citations ≥ 35% | **38.6%** | met |
| P7 | seeded p50 ≤ 6.0s | **4.57s** | met |

## P4: the thesis does not survive

The 2026-09-22 report argued reference failure is structural — a ~3B decoder has no
mechanism to check a string against a store, so it would keep emitting unverifiable
references and the renderer would be the only thing restraining it. That predicted
renderer cleanup on at least a quarter of seeded turns.

It intervened on **40 of 1,661 — 2.4%**.

| counter | occurrences |
|---|---|
| model wrote pack text unmarked (`adopted_quotes`) | 23 |
| model still reached for italics (`stripped_italics`) | 16 |
| model quoted something unbacked (`dropped_quotations`) | 5 |

Told to point rather than to italicise, the model largely stopped reaching for the
old vehicle. The limit was not the model's inability to verify a reference; it was
the contract it had been given. **Italics mean emphasis everywhere in its training
distribution, and a rule redefining them on every turn was the defect.** A typed
marker works because nothing else claims the token.

The prior paper's §5 overstates the case and should be amended to this narrower,
better-supported claim: a small model can be held to a reference contract provided
the contract does not overload a token the language already uses for something else.

## The qualification: it stopped quoting, it did not learn to quote

Of 641 seeded turns with matched evidence, only **100 (15.6%)** expanded a quote
marker. `dropped_markers` fired **251** times — markers pointing at slots that were
not there. The turns that did not point did not fabricate either; they paraphrased in
second person, which `ask-core@19` permits.

The product traded fabrication for vagueness. That is a good trade. It is not a free
one, and **no scorer in the suite measures the cost.**

## Two new problems

**The scaffolding leaks.** 34 occurrences on the seeded arm — `leak.placeholder` 24,
`leak.promptTag` 8, `leak.sectionLabel` 2 — including `[Evidence]: none` rendering
into user-visible text. **Zero** across 6,505 generated turns in Studies I and II.
The marker grammar gave the model new tokens to echo, and `ReplyRenderer` is
specified as the single choke point for Ask bodies; it did not catch these. From a
product standpoint this is worse than a fabricated quote: a fabricated quote reads as
prose, the prompt's own furniture reads as a broken app. This is also the most likely
contributor to P2's miss.

**Dates went the wrong way on the seeded arm.** P3 covered the zero-entry arm and was
met (9 → 1). Unpredicted, the seeded arm went **118 → 290** date assertions (7.3% →
17.5%), with **250 passing the suite clean**. The plain reading is that
`{{date:N}}` made dating salient; whether the extra dates are *correct* is not
measurable with the current instrument, which is itself the finding.

## Threats

- `hall.fabricatedQuote` does not measure the same thing in both studies — 050 R3
  retired its vehicle. Reported as two measurements, never one trend line. P1 was
  pre-registered as nearly guaranteed for exactly this reason.
- Model-level evidence is counters, not text: `AskResult` carries only the rendered
  body.
- The whole 050 change set moved, not the renderer alone (`ask-core@17` → `@19`).
- Conversations are not paired past turn 1 — a changed assistant produces a changed
  conversation.
- One authored seeded world; both interlocutors synthetic.
- Paraphrase, the central new cost, is asserted from counters and reading turns, not
  quantified.

## Next

1. **Fix the leak.** `ReplyRenderer` must strip `[Evidence]`, `[Today: …]` and any
   bracketed prompt furniture from the body. This is the only outright regression.
2. **Measure paraphrase.** A turn with matched evidence that neither points nor
   quotes is currently invisible. It is the cost of the fix and should be a scorer.
3. **Score dates against the pack**, now that dates are markered — a date not
   expanded from `{{date:N}}` on a seeded arm is checkable and currently unchecked.
4. **Amend spec 046 §5 / the prior paper** to the narrower contract claim.
