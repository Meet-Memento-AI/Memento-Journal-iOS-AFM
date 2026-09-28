# Study VI — pre-registration

**Written and committed before a single conversation was generated.** The point
of that ordering is that the predictions below can be wrong, and the record shows
they were made in advance.

## Question

Studies I–V measured the harness while the prompt, the renderer and the corpus
moved. Since Study IV the *prompt has not moved at all* — `ask-core@19` and
`chat-companion@1` are unchanged. What moved is which model runs underneath:
spec 051 landed `OnDeviceModelTier`, and the app now asks for AFM 3 Core Advanced
where the hardware allows it.

So Study VI is the cleanest single-variable run in the series so far:

| | Study IV (2026-09-24) | Study VI |
|---|---|---|
| base | `spec-051-reference-discipline` @ `b3dbb7d` | `study6-orchestrator` @ `36a6faa` |
| Ask prompt | `ask-core@19` | **same** |
| companion prompt | `chat-companion@1` | **same** |
| renderer | `reply-render@1` | **same** |
| arms | `empty` + `persona` | **same** |
| corpus | `Fixtures/corpus`, 262 entries | **same** |
| length | 20–50, seeded per run id | **same** |
| cast | 10×10 persona × intent | **same** |
| **model** | `apple.system.on-device` | **`apple.system.on-device.afm3-core-advanced`** |
| retrieval | pre-051 `EntryRetriever` | 051 retriever + `ContextBudget` |

Study IV's rows record `model_identifier = apple.system.on-device` on all 3,390
generated turns, with no tier fields at all; the tier work had not landed when it
ran. That is what makes the comparison clean, and it is also the thing to verify
first (P1) rather than assume.

## The trap this study has to avoid

A bigger model is not automatically a better one *for this product*. The harness's
gating violations are mostly recipe-compliance failures — `rule.multipleQuestions`
was 156 of 404 occurrences in Study IV — and a more fluent model can just as easily
write more prose, more questions and more unbacked dates. "Advanced tier" is a
claim about capability, not about obedience. Predictions below are therefore
directional and thresholded, and P2 registers latency as a **cost** to be tolerated
rather than a result to be celebrated.

The second trap: `tier_source=inferred`. The pilot log shows the simulator reports
`reason=sdkUnsupported` while still resolving to `afm3CoreAdvanced` by inference.
If the tier is inferred rather than confirmed by the SDK, the run may be measuring
a *label* and not a different model. P1 is written to make that failure visible
instead of silent, and the result section must state which it was.

## Predictions

Baselines are Study IV (`full-2026-09-24-spec051.jsonl`), recomputed with
`scripts/eval/analyze_convo_sim.py`, which reproduces every checkable published
figure under `--check-046`.

| # | Prediction | Threshold | Study IV baseline |
|---|---|---|---|
| P1 | The advanced tier actually ran | `model_identifier` ends `afm3-core-advanced` on **≥ 99%** of generated turns | `apple.system.on-device`, 100% |
| P2 | Latency rises but stays usable | persona p50 **≤ 6.5s**; empty p50 **≤ 3.0s** | 4.31s / 1.83s |
| P3 | Persona gating violations fall | **< 9.0%** of generated turns | 11.0% |
| P4 | Persona invented material falls | **≤ 2.0%** | 2.6% |
| P5 | The empty arm does not regress | gating **≤ 6.0%**, invented material **= 0** | 4.6%, 0.0% |
| P6 | The model points better | `dropped_markers` per matched turn **< 0.45** | 404/693 = 0.58 |
| P7 | Citation rate holds | persona cited **≥ 35%** | 40.3% |
| P8 | Routing is unchanged | `followup` within **±10pp** of 74.7%; `acknowledgement` and `reflectiveQuestion` still never fire | 74.7%; both 0 |
| P9 | The dominant failure is still recipe, not grounding | `rule.multipleQuestions` remains the largest single code | 156 occurrences |

P3 and P6 are the ones that carry the thesis. Studies II–III argued that reference
failure in this product is **structural** — a 3B model cannot reliably point at
evidence, so Swift has to do the quoting. If a materially larger model closes that
gap on its own, that thesis is weakened, and that is the finding. If P6 fails while
P2 passes, the product paid latency for nothing and the structural reading survives.

P8 is a negative control. Spec 051 touches model selection, not `TurnClassifier`.
If routing moves, something other than the registered variable moved with it and
the rest of the comparison is suspect.

## Design

- 100 conversations per arm, 2 arms, 20–50 messages each, seeded per run id, so
  lengths and cast cells replay identically to Studies III–V.
- Both sides on the device model; assistant through `askStream` (live retrieval,
  stance, channel, citation reconciliation), person through `evalRawGenerate`.
- Label `full-2026-09-27-tier`, on `ChatDiag27` (iOS 27.0), parallel testing off.
- Reports only. The one assertion is that the run produced output.

## Known limitations, stated up front

- **One device, one OS build.** Tier resolution is hardware-dependent by design;
  a simulator is not the population of real devices.
- **The working tree is not clean.** The branch carries in-progress spec 021
  (RevenueCat / paywall) work. None of it is on the chat path, but it is present,
  and the manifest records the SHA, not the diff.
- **`RetrievalGate.swift` was kept at this branch's version**, not Study V's, which
  references a `topMargin` field this branch's `RetrievalResult` does not have.
  It is not part of the conversation simulation.
- **`ReplyRenderStats.strippedScaffoldCount` does not exist on this branch**, so
  the `stripped_scaffold` column Study V recorded is absent here.

---

# Addendum, written mid-run (before any result was computed)

**P1 is not falsifiable on this rig, and that is the study's first finding.**

The pre-registration said P1 existed to make a silent failure visible. It did —
just earlier and more completely than expected. Checking it against the first
~600 generated turns:

```
('apple.system.on-device.afm3-core-advanced', 'afm3CoreAdvanced', 'inferred')  607
```

100% of generated turns carry the advanced-tier suffix. P1 "passes" — and the
pass means nothing, for two independent reasons.

**1. Spec 051 does not select the model.** `OnDeviceModelTier.swift`'s own header
says so: *"The tier is provenance and budget input only. On path B the OS still
chooses the model, so a mislabelled device never runs the wrong one — it only
writes the wrong suffix on a row."* `SystemLanguageModel.default` resolves to
whatever the device runs. So the registered independent variable — "the model
underneath moved" — was never a model swap. It is a **label**, plus the tier's
secondary effects on `ContextBudget` and the speculative pool key.

**2. The label is a tautology on a simulator.** The tier is inferred from
`ProcessInfo.processInfo.physicalMemory` against a 10 GB floor. Inside a
simulator that call returns the **host Mac's** memory, which here is 137 GB.
The inference therefore returns `afm3CoreAdvanced` on every simulator run on
this machine, on any device type, for any model that actually executes.

The corroborating evidence is the latency. A 20B sparse model should not be
faster than a 3B dense one on the same silicon, and the empty arm's p50 came in
at **1.64s against Study IV's 1.83s** — slightly faster, consistent with the
same model running in both.

**Why the unit tests did not catch it.** `OnDeviceModelTierTests` covers the
resolver thoroughly — sixteen cases including `test_resolver_twelveGBDevice_...`
and `test_resolver_memoryFloor_bothSides`. Every one of them *injects*
`physicalMemoryBytes`. The single production call site,
`resolveOnDeviceTierIfNeeded()`, reads `ProcessInfo` with no simulator guard and
is covered by nothing. The pure core is exhaustively tested; the one impure
input is untested.

**Consequence for the eval warehouse (spec 043).** Every row this harness has
written since 051 landed carries `model_identifier` ending `afm3-core-advanced`.
For simulator-sourced rows that suffix is unverified provenance, not a fact.
Any warehouse query that groups or filters by tier is, today, grouping on a
constant.

**What this study now measures.** Not a tier comparison. It is a clean
re-measurement of the *current pipeline* against Study IV, over the same arms,
corpus, cast, seeds and prompt — the differences being the 051 retriever and
`ContextBudget` changes, and whatever the label's effect on budget and pooling
turns out to be. P2–P9 stand as written and are still worth scoring; **P1 is
recorded as an instrument failure, not a pass.** The run continues unchanged, so
the numbers stay comparable.

No result beyond P1 had been computed when this was written.
