# Study III — pre-registration

Committed **before** any generation. Git will show this commit precedes the run
artifact, which is the only thing that makes the predictions below falsifiable
rather than a narrative fitted afterwards.

- **Registered:** 2026-09-22
- **Design:** identical to Study II — arms `empty` (0 entries) and `persona`
  (262 entries, `Fixtures/corpus`), 100 conversations each, 20–50 messages,
  same seeds, same cast, same eight scorers.
- **Only variable:** the pipeline. Study II ran `ask-core@17` with no renderer;
  Study III runs `ask-core@19` with `EvidencePack` + `ReplyRenderer` (spec 050).
- **Baselines:** `eval-archive/convo-sim/full-2026-09-21-persona.jsonl`.

## The hypothesis under test

The 2026-09-22 report argued that fabricated quotes, invented dates and the
conceded inability to count are one failure: a ~3B decoder cannot verify a
reference against an external store. It predicted that removing the opportunity
to emit an unverified reference would eliminate the failure, while the model
itself would remain non-compliant — because the limit is structural, not a
prompting deficit.

Spec 050 implements exactly that removal. So the thesis predicts a **split
result**: the product improves sharply, the model does not.

## Predictions

| # | Prediction | Threshold | Falsified if |
|---|---|---|---|
| P1 | Persona `hall.fabricatedQuote` falls sharply | < 10% of generated turns (was 56.0%, 911/1,626) | ≥ 10% |
| P2 | Empty-arm gating does not regress | ≤ 6.0% (was 5.5%) | > 6.0% |
| P3 | Invented dates on the zero-entry arm fall | ≤ 2 (was 9, of which 8 unflagged) | > 2 |
| P4 | **The model does not comply on its own** | `adopted_quotes + stripped_italics + dropped_quotations` > 0 on ≥ 25% of seeded generated turns | < 25% |
| P5 | Routing is unchanged | `followup` within ±10pp of 77.1%; `correction` remains 0 | outside either |
| P6 | Citation rate holds | seeded turns with ≥1 citation ≥ 35% (was 40.5%) | < 35% |
| P7 | Latency stays usable | seeded p50 ≤ 6.0s (was 4.50s) | > 6.0s |

**P4 is the load-bearing one.** P1 is nearly guaranteed by construction — spec
050 R3 retires italics as a quote vehicle and the renderer strips unmarked
italics, so the detector loses its vehicle whether or not the model improved.
Reporting P1 alone would repeat 046's original error: reading an absence of
violations as quality.

P4 is what distinguishes the two accounts:

- **Thesis holds** — the model keeps emitting unbacked quotations and raw
  italics, Swift keeps removing them, and the product is clean because the
  renderer is doing the work.
- **Thesis overstated** — the model largely complies once the prompt asks for
  markers instead of italics, in which case the limit was more amenable to
  instruction than the report claimed, and the report should say so.

Either outcome is publishable. The second would be the more interesting one and
would require amending the previous paper's §5.

## What will be reported regardless of outcome

- Both levels, never merged into one trend line: product (rendered body, same
  eight scorers) and model (`ReplyRenderStats` counters).
- `hall.fabricatedQuote` as two numbers from two different measurements, with
  the change in vehicle stated, rather than as a single series.
- Every prediction above marked met or falsified, including any that embarrass
  the prior report.

## Known limitations, registered in advance

- The model's pre-render text is not captured; `AskResult` carries only the
  rendered body. Model-level evidence is counters, not text.
- `ask-core@17` → `@19` means any difference is attributable to the whole spec
  050 change set, not to the renderer alone.
- The person's turns are generated from the assistant's replies, so past turn 1
  the two runs are not paired. Only distributions are comparable.
- One authored seeded world, both interlocutors synthetic — unchanged from
  Study II.
