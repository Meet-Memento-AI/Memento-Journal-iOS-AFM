# Conversation Simulation Study II — the nine-month journal

**Run:** `eval-archive/convo-sim/full-2026-09-21-persona.jsonl`, 7,048 messages,
200 conversations, 2026-09-22 01:51 → 06:41 UTC (4h50m).
**Build:** `study2-persona-arm` @ `fd294a3` — `main` (`5fa700f`, the evidence-first
Ask harness) plus the three chat commits from `session1-scorer-repair` and the build
repair in `c95e2ab`.
**Arms:** `empty` (0 entries) and `persona` (262 entries, `Fixtures/corpus`,
2025-11-01 → 2026-07-22).
**Interactive comparison:** https://claude.ai/artifact/Ub2dbsHran1gcpzPgFw7ey

Companion to [`POWER_USER_CHAT_SIMULATION.md`](POWER_USER_CHAT_SIMULATION.md) and
the 2026-09-20 study that specs
[046](../specs/046-grounding-and-evidence-discipline.md),
[047](../specs/047-conversational-state.md) and
[048](../specs/048-harness-depth-ii.md) were written from.

---

## Why this run exists

Two reasons, and the first one is a correction.

**The 2026-09-20 study never used the nine-month journal.** It is described in the
specs and the sessions doc as 100 conversations with entries and 100 without. Its
manifest says the seeded arm was `cold` — the **8-entry** `Fixtures/cold-start`
journal. `ConversationSimulation.buildArms` only ever knew `empty` and `cold`, so
the 262-entry corpus that `ChatEvalCorpus.personaCorpus` has loaded for
`ChatEvalGate` and the prompt sweep all along had never seen a twenty-to-fifty
message conversation. Adding the arm was a six-line change nobody had made.

**And that arm is the only one where the quotation scorers mean anything.** With no
corpus, every italic span is a fabricated quote by definition and every citation is
absent for a structural reason. `hall.fabricatedQuote`, `hall.uncitedQuote` and
`rule.boldNotTheirWords` cannot distinguish a model that invents from a model with
nothing to draw on until there is something to draw on.

Spec 048 R6 also requires two warehoused runs before any threshold is armed. This
is the second.

---

## The headline

| | `empty` — 0 entries | `persona` — 262 entries |
|---|---|---|
| generated turns | 1,760 | 1,626 |
| gating violations | 97 (**5.5%**) | 278 (**17.1%**) |
| invented material | 1 (**0.1%**) | 921 (**56.6%**) |
| notebook voice | 0 (0.0%) | 291 (17.9%) |
| turns carrying a citation | 0 | 659 (40.5%) |
| p50 latency | 1.70s | 4.50s |

**046's defect did not close. It moved.**

With an empty archive the pipeline is now clean. `hall.fabricatedQuote` fires once
in 1,760 turns, against roughly 200 in the 2026-09-20 archive when the repaired
scorer is replayed over it. Notebook voice — the channel that authorises headings
and journal quotation — is now unreachable with no entries, down from 36.8% of
zero-entry turns. Both of 046's findings are addressed, and the evidence-first
pipeline is what addressed them.

Give the model a journal and the same scorer fires on **911 turns, 56% of the arm**.

---

## What the scorer is actually catching

This is not the old failure. The 2026-09-20 spans were invented entries — a reply
that admitted it had no journal and then described an entry from March 12. These
are the person's **own words, italicised back at them**:

> You corrected — the stain isn't on the ceiling — it's in the socket under the
> sink. That shift changes the way the quiet settles. *Socket under the sink* — the
> drip now speaks louder.

> You see the ink bleeding — *Page 73 — ink bleeding near the bottom* — the mark
> pushing outward like a slow leak.

The person said "socket under the sink" one turn earlier. Under the ask@14 contract
italics are reserved for an exact journal quote, so every one of these reads as an
invented entry. `rule.boldNotTheirWords` (72) and `hall.uncitedQuote` (54) catch the
same behaviour through neighbouring checks.

**This needs a decision before any threshold is armed, and it is a real fork:**

1. **The model should stop italicising non-corpus text.** Echoing someone's phrasing
   is reasonable conversational behaviour; marking it up as a quote is not. This is
   a schema or reconciliation fix, in the spirit of 037's "code decides, the model
   renders" — strip emphasis from any span not found in the corpus, rather than
   asking the prompt to restrain itself.
2. **Or the scorer is conflating two failures of very different severity.**
   "Invented an entry that does not exist" and "quoted the user back to themselves"
   are both contract breaks, but only the first is the one 046 calls the single most
   damaging failure mode for a journal app. One code cannot carry both.

Arming `hall.fabricatedQuote` at its current definition would gate on a 56% rate
mostly composed of the second thing. 046 R1 keeps it report-only, which is correct,
and this is the evidence for why that caution was right.

---

## Nothing scores dates, and dates are where it still invents

Found by a peer session while sourcing a comparison span, and it is the clearest
gap either study has turned up.

A 2026-09-20 turn on the `cold` arm renders this, in notebook voice:

> I don't see anything from that stretch—the kettle doesn't appear in the recent
> turns.
>
> ### *March 12 – Argument with Dario about the move*

The quote is **real and verbatim** — `Fixtures/cold-start` entry `cs-02` reads
"Argument with Dario about the move." The date is invented. Every cold-start entry
is dated relatively (`daysAgo` 1, 3, 5, 8, 11, 15, 20, 26), so `cs-02` is three days
old and no March 12 entry exists to cite. The reply also denies having anything and
then quotes an entry in the same breath, which is the cite-then-deny hedge
`stanceMatchingEvidence` exists to prevent.

The only code that fired was `hall.uncitedQuote` — correct as far as it goes, since
the span was quoted without attribution, but it names the wrong failure. What the
model got wrong is the date on a true quote.

Measured across both runs, counting a month-name-plus-day assertion in the reply body:

| run · arm | generated | assert a date | of those, **no** gating violation |
|---|---|---|---|
| 2026-09-20 · `empty` | 1,597 | 1 (0.1%) | 1 (100%) |
| 2026-09-20 · `cold` | 1,522 | 73 (4.8%) | 48 (65.8%) |
| Study II · `empty` | 1,760 | 9 (0.5%) | 8 (88.9%) |
| Study II · `persona` | 1,626 | 118 (7.3%) | 83 (70.3%) |

**No scorer targets date assertions**, so between two thirds and nine in ten of them
pass clean. (The "no violation" column is gating-only, like every other rate here:
`hall.fabricatedQuote` is report-only, so a dated turn that trips only that code
still counts as passing clean — which is the situation, not a rounding choice.) On the seeded arms a date can legitimately be right — `Fixtures/corpus` is
absolutely dated — so 118 is not 118 errors. On the `empty` arm every date assertion
is necessarily invented, and that is the number that should be zero: it is **9, up
from 1**, in a build that already carries `2c0d2f5`'s `[Today: …]` prompt anchor.

Three things follow:

1. **The anchor did not fix it and may have made it worse.** `todayLine()` gives the
   model a clock; it did not stop the model attaching dates to things. The
   `PromptDateAnchorTests` assert the line is present in the prompt, which is a
   different claim from the model using it correctly.
2. **There is no `hall.fabricatedDate`.** 046's motivating example — "I don't see
   anything from that stretch — the entry from March 12 shows a spike in missed
   classes" — is quoted in `2c0d2f5`'s own commit message, and nothing in
   `ChatEvalScoring` measures it. That turn, on the zero-entry arm of the 2026-09-20
   run, carries an empty `violations` array.
3. **A grounding failure hiding inside an attribution code is the same conflation as
   the fabricated-quote one.** Two different defects are reaching one name again,
   which is the pattern 048 R1 was written about.

A date scorer is cheap and checkable without a model: entry dates are known, so any
month-day assertion either matches a cited entry's `createdAt` or it does not.

---

## 047: the routing collapse moved too

| | 2026-09-20 | Study II |
|---|---|---|
| `TurnType.followup` | 5 of 3,492 (**0.14%**) | 2,718 of 3,524 (**77.1%**) |
| `thread` channel | 5 turns | 1,261 turns |
| `correction` | — | **0** |
| `reflectiveQuestion` | — | **0** |
| `acknowledgement` | — | **0** |

`followup` was dead and now dominates; `thread` went from 5 turns across 200
conversations to 1,261. 047's finding 2 is addressed in the sense that the branch is
reachable.

Whether it is *calibrated* is a separate question this run does not settle. Four
turns in five classify as `followup`, and three cases never fire at all — including
`correction`, on a run whose cast contains a persona briefed to misremember details
and then correct itself, and whose opening intents include a flat contradiction
("You told me before that I'd been sleeping fine. That's not right at all."). A
classifier that routes almost everything to one case is not obviously better
calibrated than one that never reached it. The confusion matrix is in the artifact
and in `analyze_convo_sim.py`'s output, zero rows included, which is what 048 R2
asked for.

---

## Personas: every single one does worse with a journal

| persona | `empty` | `persona` | delta |
|---|---|---|---|
| p06-planner | 2.2% | 24.1% | +21.9pp |
| p05-griever | 2.6% | 22.5% | +19.9pp |
| p10-analyst | 4.6% | 18.8% | +14.2pp |
| p09-guarded | 3.2% | 16.7% | +13.5pp |
| p03-skeptic | 4.3% | 16.8% | +12.6pp |
| p02-spiller | 5.6% | 15.1% | +9.5pp |
| p01-clipped | 7.1% | 15.8% | +8.7pp |
| p08-chatty | 7.5% | 14.1% | +6.6pp |
| p04-tester | 7.6% | 12.2% | +4.6pp |
| p07-nostalgic | 11.7% | 13.3% | +1.6pp |

All ten, which is a different shape from 2026-09-20, where only three personas were
worse with the 8-entry journal and `p06-planner` was the one it helped *most*
(−21.1pp there, +21.9pp here). The sign did not just shrink; it inverted for seven
of the ten.

Read that as a property of the failure mode rather than of the personas: quoting the
user back at them does not depend on who the user is, so a defect that fires on any
conversational turn spreads evenly across the cast. It is also why the persona
breakdown has to be split by arm — pooled, this table says nothing.

---

## What this run cannot tell you

**The headline comparison is confounded.** Study II changed the journal *and* the
pipeline. Only two comparisons hold a variable still:

- **pipeline effect** — the `empty` arm across the two studies (same empty world)
- **world effect** — Study II's two arms (same pipeline, 0 against 262 entries)

The 8-entry `cold` arm crosses both axes and cannot be cleanly compared to either.
The artifact leads with a validity grid for this reason.

**The corpus is stale relative to today.** It ends 2026-07-22, so the newest entry
is 62 days old and the median cited entry is **169 days** old. Intent
`i03-temporal` ("What did I write about last Tuesday?") has no correct answer on
this arm. That is a legitimate no-match probe, but it is not the same thing as
asking a *current* journal about last Tuesday, and no arm in either study does that.

**One world is not journals in general.** `Fixtures/corpus` is a single authored
persona. 048 R3's counterfactual pairs — two worlds differing in exactly one
property, ground truth attached — are what would isolate a cause, and they are not
in this run.

**Both sides are synthetic.** The person is a persona-briefed session of the same
on-device model. 42 designed refusals and 9 fallback person turns on the `empty`
arm are the harness's own guardrail, not facts about the app.

---

## Two figures in spec 046 do not hold

Found while building `analyze_convo_sim.py --check-046`, which re-derives the
published numbers from the archive. Five reproduce exactly: 3,119 generated turns,
1,597 on the zero-entry arm, 588 of those in notebook voice, the 38.3% notebook
rate, and `followup` on 5 of 3,492.

**"212 zero-entry turns present invented journal material" is a replay figure.**
`hall.fabricatedQuote` appears in `full-2026-09-20.jsonl` exactly **zero** times,
because that run was scored with the regex that could not compile. 212 came from
re-running the repaired scorer over the archived bodies and cannot be recomputed
from the recorded violations. The archive's own grounding codes are
`hall.uncitedQuote` 7 and `rule.boldNotTheirWords` 68.

**The "38.3% vs 6.8%" pair is not measured the same way on each side.** 38.3% counts
gating codes only; 6.8% lands only with the report-only `gen.hitTokenCap` counted
in. No `gen.*` code ever fired in notebook voice, which is why only the companion
figure moves. Gating-only throughout, the contrast is **38.3% against 5.6%** — wider
than published, not narrower, so 046's argument survives its own arithmetic error.
Every rate in this document and in the artifact is gating-only, matching
`ChatEvalScoring.gating`.

---

## Reproducing this

```bash
# the run (~5 hours, serial; needs Xcode 27 for the iOS 27 FoundationModels SDK)
TEST_RUNNER_CONVO_SIM=1 TEST_RUNNER_CONVO_SIM_RUNS=100 \
TEST_RUNNER_CONVO_SIM_ARMS=empty,persona \
TEST_RUNNER_CONVO_SIM_LABEL=full-2026-09-21-persona \
TEST_RUNNER_CONVO_SIM_GIT_SHA=$(git rev-parse HEAD) \
TEST_RUNNER_CONVO_SIM_GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
DEVELOPER_DIR=/path/to/Xcode-27.app/Contents/Developer \
xcodebuild test -scheme withMemento \
  -destination 'platform=iOS Simulator,id=<iOS 27 device>' \
  -parallel-testing-enabled NO \
  -only-testing:withMementoTests/ConversationSimulation

# the analysis — no figure in this document is hand-counted
scripts/eval/analyze_convo_sim.py eval-archive/convo-sim/full-2026-09-21-persona.jsonl
scripts/eval/analyze_convo_sim.py --check-046 eval-archive/convo-sim/full-2026-09-20.jsonl

# the artifact
scripts/eval/export_convo_sim_json.py \
  --run "Study I:eval-archive/convo-sim/full-2026-09-20.jsonl" \
  --run "Study II:eval-archive/convo-sim/full-2026-09-21-persona.jsonl" \
  --out eval-archive/convo-sim/aggregates.json
scripts/eval/build_comparison_page.py --data eval-archive/convo-sim/aggregates.json \
  --template eval-archive/page.template.html --out eval-archive/grounding-study-ii.html
```

Never `simctl erase` the eval simulator — it destroys the on-device model assets and
the study skips silently.

---

## Throughput, for anyone sizing the next run

`ModelRuntimeGate` serialises every generation, so this is a hard constraint and not
a tuning parameter.

| arm | p50 | p90 | max |
|---|---|---|---|
| `empty` | 1.70s | 2.19s | 4.00s |
| `persona` | 4.50s | 7.36s | 16.64s |

The 262-entry arm is **2.6× slower per turn** than the empty one: retrieval over a
mature archive, and a longer prompt to generate against. 200 conversations at 20–50
messages cost 4h50m with one arm of each. A study that is all `persona` should be
budgeted at roughly seven hours for the same 200, and 048 R3's arithmetic for
six-figure sample counts remains not executable here.

---

## Recommended next steps

1. **Do not arm `hall.fabricatedQuote`.** Resolve the fork above first — split the
   code, or stop the model italicising non-corpus spans. 048 R6's two-run rule is
   satisfied, but the second run is the one that shows the definition is wrong.
2. **Decide whether `followup` at 77% is intended**, and why `correction` never
   fires on a cast built to produce corrections. This is 047's remaining work and
   the confusion matrix is now the instrument for it.
3. **Refresh `Fixtures/corpus` to relative dates**, the way `Fixtures/cold-start`
   already uses `daysAgo`. No arm in either study can currently ask a current
   journal about last week.
4. **Add a date scorer.** No check targets an asserted date, so 89% of the
   zero-entry arm's invented dates pass clean, and the count went up rather than
   down after the prompt anchor landed. It needs no model to evaluate.
5. **Land 048 R3's counterfactual pairs.** Contrast, not volume, is what both
   studies found things with, and a 56% rate on one authored world cannot separate
   model behaviour from corpus properties.
